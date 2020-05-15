# Application dependencies
require "email"
require "log_helper"
require "active-model"
require "action-controller"

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

# Logging configuration
if App.running_in_production?
  log_level = Log::Severity::Info
  Log.builder.bind "*", :warning, App::LOG_BACKEND
else
  log_level = Log::Severity::Debug
  Log.builder.bind "*", :info, App::LOG_BACKEND
end
Log.builder.bind "action-controller.*", log_level, App::LOG_BACKEND
Log.builder.bind "#{App::NAME}.*", log_level, App::LOG_BACKEND
Log.builder.bind "e_mail.*", log_level, App::LOG_BACKEND

# Filter out sensitive params that shouldn't be logged
filter_params = ["password", "bearer_token"]
keeps_headers = ["X-Request-ID"]

# Add handlers that should run before your application
ActionController::Server.before(
  ActionController::ErrorHandler.new(App.running_in_production?, keeps_headers),
  ActionController::LogHandler.new(filter_params),
)

# Set SMTP client configuration
SMTP_CONFIG = EMail::Client::Config.new(
  App::SMTP_SERVER,
  App::SMTP_PORT
)
SMTP_CONFIG.use_auth(App::SMTP_USER, App::SMTP_PASS) if App.smtp_authenticated?
case App::SMTP_SECURE
when "SMTPS"
  SMTP_CONFIG.use_tls(EMail::Client::TLSMode::SMTPS)
  SMTP_CONFIG.tls_context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
when "STARTTLS"
  SMTP_CONFIG.use_tls(EMail::Client::TLSMode::STARTTLS)
  SMTP_CONFIG.tls_context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
when ""
else
  raise "unknown SMTP_SECURE setting: #{App::SMTP_SECURE.inspect}"
end

# Start monitoring
LOADER = PlaceOS::Triggers::Loader.new
LOADER.load!
