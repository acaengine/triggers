# Application dependencies
require "log_helper"
require "placeos-log-backend"

# Application code
require "./constants"

# Logging configuration
log_level = App.running_in_production? ? Log::Severity::Info : Log::Severity::Debug
log_backend = PlaceOS::LogBackend.log_backend

Log.setup "*", :warn, log_backend
Log.builder.bind "action-controller.*", log_level, log_backend
Log.builder.bind "#{App::NAME}.*", log_level, log_backend
Log.builder.bind "e_mail.*", log_level, log_backend
