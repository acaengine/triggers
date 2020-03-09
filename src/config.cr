# Application dependencies
require "email"
require "active-model"
require "action-controller"
PROD = ENV["SG_ENV"]? == "production"

# Logging configuration
ActionController::Logger.add_tag request_id
logger = ActionController::Base.settings.logger
logger.level = PROD ? Logger::INFO : Logger::DEBUG

# Required to convince Crystal this file is not a module
abstract class PlaceOS::Driver; end

class PlaceOS::Driver::Protocol; end

# Application code
require "./constants"
require "./controllers/application"
require "./controllers/*"
require "./triggers"

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

# Set SMTP client configuration
SMTP_CONFIG = EMail::Client::Config.new(
  ENV["SMTP_SERVER"]? || "smtp.example.com",
  (ENV["SMTP_PORT"]? || 25).to_i
)

user_name = ENV["SMTP_USER"]? || ""
user_pass = ENV["SMTP_PASS"]? || ""
smtp_tls = (ENV["SMTP_SECURE"]? || "false") == "true"

SMTP_CONFIG.logger = logger
SMTP_CONFIG.use_auth(user_name, user_pass) unless user_pass.empty?
# SMTP_CONFIG.use_tls = smtp_tls

LOADER = PlaceOS::Triggers::Loader.new
LOADER.load!
