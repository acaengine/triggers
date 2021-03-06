require "secrets-env"

module App
  NAME    = "triggers"
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}

  Log           = ::Log.for(NAME)
  LOG_STDOUT    = ActionController.default_backend
  LOGSTASH_HOST = ENV["LOGSTASH_HOST"]?
  LOGSTASH_PORT = ENV["LOGSTASH_PORT"]?

  def self.log_backend
    if logstash_host = LOGSTASH_HOST.presence
      logstash_port = LOGSTASH_PORT.try(&.to_i?) || abort("LOGSTASH_PORT is either malformed or not present in environment")

      # Logstash UDP Input
      logstash = UDPSocket.new
      logstash.connect logstash_host, logstash_port
      logstash.sync = false

      # debug at the broadcast backend level, however this will be filtered
      # by the bindings
      backend = ::Log::BroadcastBackend.new
      backend.append(LOG_STDOUT, :trace)
      backend.append(ActionController.default_backend(
        io: logstash,
        formatter: ActionController.json_formatter
      ), :trace)
      backend
    else
      LOG_STDOUT
    end
  end

  ENVIRONMENT = ENV["SG_ENV"]? || "development"

  DEFAULT_PORT          = (ENV["SG_SERVER_PORT"]? || 3000).to_i
  DEFAULT_HOST          = ENV["SG_SERVER_HOST"]? || "127.0.0.1"
  DEFAULT_PROCESS_COUNT = (ENV["SG_PROCESS_COUNT"]? || 1).to_i

  SMTP_SERVER = ENV["SMTP_SERVER"]? || "smtp.example.com"
  SMTP_PORT   = (ENV["SMTP_PORT"]? || 25).to_i
  SMTP_USER   = ENV["SMTP_USER"]? || ""
  SMTP_PASS   = ENV["SMTP_PASS"]? || ""
  SMTP_SECURE = ENV["SMTP_SECURE"]? || ""

  CORE_NAMESPACE = "core"
  CORE_DISCOVERY = HoundDog::Discovery.new(CORE_NAMESPACE)

  def self.discovery
    CORE_DISCOVERY
  end

  def self.smtp_authenticated?
    !SMTP_USER.empty?
  end

  def self.running_in_production?
    ENVIRONMENT == "production"
  end
end
