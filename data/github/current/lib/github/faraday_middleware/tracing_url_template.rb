# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that sets the url.template attributes to the
    # OpenTelemetry::Common::HTTP::ClientContext
    class TracingUrlTemplate < ::Faraday::Middleware

      # The URL template builder to use for generating the url.template
      # attribute from an HTTP Method and path.
      attr_reader :url_template_builder

      sig { params(app: T.untyped, options: T::Hash[Symbol, T.untyped]).void }
      def initialize(app, options = {})
        super(app)
        @options = options
      end

      sig { params(env: Faraday::Env).returns(T.untyped) }
      def call(env)
        return @app.call(env) unless template = env.request&.context&.dig("url.template").presence

        OpenTelemetry::Common::HTTP::ClientContext.with_attributes("url.template" => template) do
          @app.call(env)
        end
      end
    end
  end
end
