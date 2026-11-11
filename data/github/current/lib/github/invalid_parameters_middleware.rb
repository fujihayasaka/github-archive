# typed: true
# frozen_string_literal: true

module GitHub
  # Rack middleware to rescue invalid parameters and return a 400 error
  class InvalidParametersMiddleware
    CONTENT_TYPE  = GitHub::Middleware::Constants::APPLICATION_JSON
    MESSAGE       = "Malformed request".freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue Rack::Utils::ParameterTypeError, Rack::Utils::InvalidParameterError, RangeError => e
      [400, { "Content-Type" => CONTENT_TYPE }, [{ message: MESSAGE }.to_json]]
    end
  end
end
