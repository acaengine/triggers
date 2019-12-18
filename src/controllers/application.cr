require "uuid"

abstract class Application < ActionController::Base
  before_action :set_request_id

  # This makes it simple to match client requests with server side logs.
  # When building microservices this ID should be propagated to upstream services.
  def set_request_id
    response.headers["X-Request-ID"] = logger.request_id = request.headers["X-Request-ID"]? || UUID.random.to_s
  end

  # 404 if resource not present
  rescue_from RethinkORM::Error::DocumentNotFound do |error|
    logger.debug error.inspect_with_backtrace
    head :not_found
  end
end
