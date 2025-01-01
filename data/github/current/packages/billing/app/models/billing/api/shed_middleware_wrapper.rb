# typed: true
# frozen_string_literal: true

require "faraday"
require "shed"

module Billing
  module Api
    # {ShedMiddlewareWrapper} wraps the `Shed::FaradayMiddleware` to be
    # conditionally called only if the `billing_api_shed_middleware` feature flag
    # is enabled.
    class ShedMiddlewareWrapper < Faraday::Middleware
      def initialize(app)
        @app = app
        @shed = Shed::FaradayMiddleware.new(@app)
      end

      def call(env)
        if GitHub.flipper[:billing_api_shed_middleware].enabled?
          @shed.call(env)
        else
          @app.call(env)
        end
      end
    end
  end
end
