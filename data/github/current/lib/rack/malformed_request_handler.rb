# typed: true
# frozen_string_literal: true

module Rack
  # This middleware is intended to intercept request-parsing exceptions that originate in the Application, which
  # is different than GitHub::InvalidParametersMiddleware which intercepts exceptions that originate in Rack.
  # This middleware captures known exceptions and ensures they are not reported to Failbot or GHES-inserted middleware
  # like Sentry. Unknown exceptions will be re-raised with a new message to avoid PII leakage if they are reported.
  class MalformedRequestHandler
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue ArgumentError => error
      error_string = error.to_s

      if error_string =~ /^invalid %-encoding/
        GitHub.dogstats.increment("request.malformed_request_error.invalid_percent_encoding")
        malformed_request_response
      elsif error_string =~ /invalid byte sequence in UTF-8/
        GitHub.dogstats.increment("request.malformed_request_error.invalid_byte_sequence_in_utf8")
        malformed_request_response
      else
        GitHub.dogstats.increment("request.malformed_request_error.unknown")
        GitHub.logger.error(error, "code.namespace": "MalformedRequestHandler", "code.function": "call")

        # Re-raise other exceptions but prevent PII leakage in error message; Exception#cause may still contain the original error.
        raise error.exception("malformed request").tap { |new_error| new_error.set_backtrace(error.backtrace) }
      end
    end

    private

    def malformed_request_response
      [400, { "Content-Type" => "application/json" }, [{ message: "400 Bad Request" }.to_json]]
    end
  end
end
