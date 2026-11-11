# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that sets telemetry attributes (url.template, peer.service, etc.)
    # to the OpenTelemetry::Common::HTTP::ClientContext
    class TracingAttributes < ::Faraday::Middleware

      sig { params(app: T.untyped, options: T::Hash[Symbol, T.untyped]).void }
      def initialize(app, options = {})
        super(app)
        @options = options
      end

      sig { params(env: Faraday::Env).returns(T.untyped) }
      def call(env)
        attributes = {}

        if template = env.request&.context&.dig("url.template").presence
          attributes["url.template"] = template
        end

        if peer_service = env.request&.context&.dig("peer.service").presence
          attributes["peer.service"] = peer_service
        end

        return @app.call(env) if attributes.empty?

        OpenTelemetry::Common::HTTP::ClientContext.with_attributes(attributes) do
          @app.call(env)
        end
      end
    end
  end
end
