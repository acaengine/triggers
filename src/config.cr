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
require "./placeos-triggers"

# Server required after application controllers
require "action-controller/server"

# Logging configuration
log_level = App.running_in_production? ? Log::Severity::Info : Log::Severity::Debug
log_backend = App.log_backend

Log.setup "*", :warn, log_backend
Log.builder.bind "action-controller.*", log_level, log_backend
Log.builder.bind "#{App::NAME}.*", log_level, log_backend
Log.builder.bind "e_mail.*", log_level, log_backend

# Filter out sensitive params that shouldn't be logged
filter_params = ["password", "bearer_token"]
keeps_headers = ["X-Request-ID"]

# Add handlers that should run before your application
ActionController::Server.before(
  ActionController::ErrorHandler.new(App.running_in_production?, keeps_headers),
  ActionController::LogHandler.new(filter_params, ms: true),
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
