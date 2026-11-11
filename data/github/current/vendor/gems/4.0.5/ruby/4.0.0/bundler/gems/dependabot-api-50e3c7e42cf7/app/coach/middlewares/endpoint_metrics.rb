# frozen_string_literal: true

require "renderer"

module Middlewares
  class EndpointMetrics < Coach::Middleware
    def call
      endpoint = config[:route_class]&.to_s || "unknown"

      MetricsClient.increment("request", tags: { endpoint: })

      next_middleware.call
    end
  end
end
