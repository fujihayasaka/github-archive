# typed: true
# frozen_string_literal: true

# TODO: This file is suppose to replace the Datadog middleware.
# For now, this is a copy so we can test it first, before a big switch.
module GitHub
  module FaradayMiddleware
    # Faraday Middleware for opentracing our Spokes client
    #
    # It would be "better" to use faraday/tracer middleware rather than write our
    # own, however  the current version doesn't support our old faraday. It's not
    # really *that* hard to build a purpose built middlware so we can just deal
    # with it.
    class AsyncDuration < Faraday::Middleware
      GITHUB_ALLOY_DURATION_HEADER = "X-GitHub-Alloy-Duration".freeze

      # Create a new Faraday Tracer middleware.
      #
      # @param app The faraday application/middlewares stack.
      def initialize(app, options = {})
        super(app)
      end

      def call(env)
        if env.parallel?
          resp = @app.call(env)
          # If we are using the ConcurrentAdapter from ConcurrentFaraday, we should have
          # a FutureResponse (promise).
          if resp.is_a?(ConcurrentFaraday::FutureResponse)
            # If we have a FutureResponse, subscribe to fullfillment and rejection
            # in order to listen to the instrumentation event.
            # Even when the request fails, we want to ensure that the instrumentation
            # will be sent to DD.
            log_stats = proc do |_v|
              event = resp.instrument_event
              env.response_headers[GITHUB_ALLOY_DURATION_HEADER] = event.duration
            end
            resp.then(log_stats, log_stats)
          end
        end

        resp
      end

    end
  end
end
