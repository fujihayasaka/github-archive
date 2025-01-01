# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday middleware that allows an increasing open_timeout.
    class IncreasingTimeout < ::Faraday::Middleware
      def initialize(app, options = {})
        super(app)
        @factor = options[:factor]
      end

      def call(env)
        env.params ||= {}
        if env.params[:is_retry]
          env.request[:open_timeout] *= @factor
        end
        env.params[:is_retry] = true

        @app.call(env)
      end
    end
  end
end
