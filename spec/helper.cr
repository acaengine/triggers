require "secrets-env"
require "spec"
require "base64"
require "random"
require "webmock"
require "placeos-log-backend"
require "rethinkdb-orm"

# Prepare for node discovery
WebMock.stub(:post, "http://127.0.0.1:2379/v3beta/kv/range")
  .with(body: "{\"key\":\"c2VydmljZS9jb3JlLw==\",\"range_end\":\"c2VydmljZS9jb3JlMA==\"}", headers: {"Content-Type" => "application/json"})
  .to_return(body: {
    count: "1",
    kvs:   [{
      key:   "c2VydmljZS9jb3JlLw==",
      value: Base64.strict_encode("http://127.0.0.1:9001"),
    }],
  }.to_json)

# We'll let the watch request hang
WebMock.stub(:post, "http://127.0.0.1:2379/v3beta/watch")
  .with(body: "{\"create_request\":{\"key\":\"c2VydmljZS9jb3Jl\",\"range_end\":\"c2VydmljZS9jb3Jm\"}}", headers: {"Content-Type" => "application/json"})
  .to_return(body_io: IO::Stapled.new(*IO.pipe))

# Triggers code
Log.setup "*", :trace, PlaceOS::LogBackend::LOG_STDOUT
Log.builder.bind "action-controller.*", :trace, PlaceOS::LogBackend::LOG_STDOUT
Log.builder.bind "#{App::NAME}.*", :trace, PlaceOS::LogBackend::LOG_STDOUT
Log.builder.bind "e_mail.*", :trace, PlaceOS::LogBackend::LOG_STDOUT

require "../src/config"
require "../src/placeos-triggers"

# Generators for Engine models
require "./generator"

# Configure DB
db_name = "test"

RethinkORM.configure do |settings|
  settings.db = db_name
end

# Clear test tables on exit
Spec.after_suite do
  RethinkORM::Connection.raw do |q|
    q.db(db_name).table_list.for_each do |t|
      q.db(db_name).table(t).delete
    end
  end
end

# Models
#################################################################

# Pretty prints document errors
def inspect_error(error : RethinkORM::Error::DocumentInvalid)
  errors = error.model.errors.map do |e|
    {
      field:   e.field,
      message: e.message,
    }
  end
  pp! errors
end
