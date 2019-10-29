# Application dependencies
require "action-controller"
PROD = ENV["SG_ENV"]? == "production"

# Logging configuration
ActionController::Logger.add_tag request_id
logger = ActionController::Base.settings.logger
logger.level = PROD ? Logger::INFO : Logger::DEBUG

# Required to convince Crystal this file is not a module
abstract class ACAEngine::Driver; end

class ACAEngine::Driver::Protocol; end

# Application code
require "./constants"
require "./controllers/application"
require "./controllers/*"
require "./engine-triggers"

# Server required after application controllers
require "action-controller/server"

# Filter out sensitive params that shouldn't be logged
filter_params = ["password", "bearer_token"]

# Add handlers that should run before your application
ActionController::Server.before(
  HTTP::ErrorHandler.new(!PROD),
  ActionController::LogHandler.new(PROD ? filter_params : nil),
  HTTP::CompressHandler.new
)
