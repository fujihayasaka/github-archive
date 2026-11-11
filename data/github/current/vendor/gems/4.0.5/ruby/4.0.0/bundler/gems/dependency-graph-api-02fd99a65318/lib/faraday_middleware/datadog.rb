# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday Middleware for DataDog our Spokes client
    #
    # It would be "better" to use faraday/tracer middleware rather than write our
    # own, however  the current version doesn't support our old faraday. It's not
    # really *that* hard to build a purpose built middleware so we can just deal
    # with it.
    class Datadog < Faraday::Middleware
      # Create a new Faraday Tracer middleware.
      #
      # @param app The faraday application/middlewares stack.
      # @param service_name [String, nil] Remote service name (for some unspecified definition of "service")
      # @param stats Stats implementation
      def initialize(app, options = {})
        super(app)
        @service_name = options[:service_name] || "unknown"
        @dogstats = options[:stats]
      end

      def call(env)
        start = Time.now
        success = false

        # To promote use of newer distribution metrics, new tags shouldn't be
        # added to the legacy timing metric.
        # See https://github.com/github/github/pull/157670#pullrequestreview-502020056
        legacy_tags = [
          "method:#{env[:method]}",
          "path:#{env[:url].request_uri}",
        ]

        tags = []

        begin
          @app.call(env).on_complete do
            legacy_tags << "status:#{env[:status]}"

            if env[:status] < 400
              success = true
            end
          end
        rescue => e
          legacy_tags << "err:#{e.class.name}"
          raise
        ensure
          legacy_tags << "success:#{success}"
          ms = (Time.now - start) * 1000
          @dogstats.distribution("rpc.#{@service_name}.dist_time", ms, tags: legacy_tags + tags)
        end
      end
    end
  end
end
