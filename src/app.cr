require "option_parser"
require "http/client"
require "./constants"

# Server defaults
port = App::DEFAULT_PORT
host = App::DEFAULT_HOST
process_count = App::DEFAULT_PROCESS_COUNT

# Command line options
OptionParser.parse(ARGV.dup) do |parser|
  parser.banner = "Usage: #{App::NAME} [arguments]"

  parser.on("-b HOST", "--bind=HOST", "Specifies the server host") { |h| host = h }
  parser.on("-p PORT", "--port=PORT", "Specifies the server port") { |p| port = p.to_i }

  parser.on("-w COUNT", "--workers=COUNT", "Specifies the number of processes to handle requests") do |w|
    process_count = w.to_i
  end

  parser.on("-r", "--routes", "List the application routes") do
    ActionController::Server.print_routes
    exit 0
  end

  parser.on("-v", "--version", "Display the application version") do
    puts "#{App::NAME} v#{App::VERSION}"
    exit 0
  end

  parser.on("-c URL", "--curl=URL", "Perform a basic health check by requesting the URL") do |url|
    begin
      response = HTTP::Client.get url
      exit 0 if (200..499).includes? response.status_code
      puts "health check failed, received response code #{response.status_code}"
      exit 1
    rescue error
      error.inspect_with_backtrace(STDOUT)
      exit 2
    end
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit 0
  end
end

# Load the routes
puts "Launching #{App::NAME} v#{App::VERSION}"

# Requiring config here ensures that the option parser runs before
# we attempt to connect to databases etc.
require "./logging"
require "./config"
server = ActionController::Server.new(port, host)

# Start clustering
server.cluster(process_count, "-w", "--workers") if process_count != 1

terminate = Proc(Signal, Nil).new do |signal|
  puts " > terminating gracefully"
  spawn(same_thread: true) { server.close }
  signal.ignore
end

# Detect ctr-c to shutdown gracefully
# Docker containers use the term signal
Signal::INT.trap &terminate
Signal::TERM.trap &terminate

# Allow signals to change the log level at run-time
logging = Proc(Signal, Nil).new do |signal|
  log_level = signal.usr1? ? Log::Severity::Debug : Log::Severity::Info
  log_backend = App.log_backend
  puts " > Log level changed to #{log_level}"
  Log.builder.bind "action-controller.*", log_level, log_backend
  Log.builder.bind "#{App::NAME}.*", log_level, log_backend
  Log.builder.bind "e_mail.*", log_level, log_backend
  EMail::Client.log_level = log_level
  signal.ignore
end

# Turn on DEBUG level logging `kill -s USR1 %PID`
# Default production log levels (INFO and above) `kill -s USR2 %PID`
Signal::USR1.trap &logging
Signal::USR2.trap &logging

# Start the server
server.run do
  puts "Listening on #{server.print_addresses}"
end

# Shutdown message
puts "#{App::NAME} leaps through the veldt\n"
