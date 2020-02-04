require "option_parser"
require "http/client"

module ACAEngine::Triggers
end

# Server defaults
port = (ENV["SG_SERVER_PORT"]? || 3000).to_i
host = ENV["SG_SERVER_HOST"]? || "127.0.0.1"
process_count = (ENV["SG_PROCESS_COUNT"]? || 1).to_i

# Command line options
OptionParser.parse(ARGV.dup) do |parser|
  parser.banner = "Usage: #{ACAEngine::Triggers::APP_NAME} [arguments]"

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
    puts "#{ACAEngine::Triggers::APP_NAME} v#{ACAEngine::Triggers::VERSION}"
    exit 0
  end

  parser.on("-h URL", "--health=URL", "Perform a basic health check by requesting the URL") do |url|
    begin
      response = HTTP::Client.get url
      exit 0 if (200..499).includes? response.status_code
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
puts "Launching #{ACAEngine::Triggers::APP_NAME} v#{ACAEngine::Triggers::VERSION}"

# Requiring config here ensures that the option parser runs before
# we attempt to connect to databases etc.
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
  level = signal.usr1? ? Logger::DEBUG : Logger::INFO
  puts " > Log level changed to #{level}"
  ActionController::Base.settings.logger.level = level
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
puts "#{ACAEngine::Triggers::APP_NAME} leaps through the veldt\n"
