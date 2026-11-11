# frozen_string_literal: true

# cribbed from dotcom
module Middleware
  # Handles ActionController::UnknownHttpMethod & ActionController::BadRequest
  # exceptions, returns the appropriate 400 error code.
  class BadRequest
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue ActionController::UnknownHttpMethod, ActionDispatch::Http::MimeNegotiation::InvalidType => e
      [400, { "content-type" => "text/plain" }, ["Bad Request: #{e}"]]
    rescue ActionController::BadRequest => e
      raise e unless handled_bad_request_error?(e)

      [400, { "content-type" => "text/plain" }, ["Bad Request: #{e}"]]
    end

    def handled_bad_request_error?(error)
      error.message.include?("Invalid path parameters") || error.message.include?("Invalid query parameters")
    end
  end
end
