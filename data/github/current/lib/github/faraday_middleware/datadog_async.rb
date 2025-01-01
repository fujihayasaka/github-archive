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
    class DatadogAsync < Faraday::Middleware
      # Create a new Faraday Tracer middleware.
      #
      # @param app The faraday application/middlewares stack.
      # @param service_name [String, nil] Remote service name (for some
      #        unspecified definition of "service")
      # @param catalog_service [String, nil] Catalog service name (if different from service_name)
      # @param stats Stats implementation
      # @tracked_latency_slos [Hash, nil] Latency SLO metrics to be reported to Datadog
      # @tracked_availability_slos [Array, nil] Availability SLO metrics to be reported to Datadog
      def initialize(app, options = {})
        super(app)
        @service_name = options[:service_name] || "unknown"
        @catalog_service = options[:catalog_service] || @service_name
        @dogstats = options[:stats]
        @custom_tags = options[:custom_tags] || []
        @tracked_latency_slos = options[:tracked_latency_slos] || {}
        @tracked_availability_slos = options[:tracked_availability_slos] || []
        @events = []
      end

      def call(env)
        # To promote use of newer distribution metrics, new tags shouldn't be
        # added to the legacy timing metric.
        # See https://github.com/github/github/pull/157670#pullrequestreview-502020056
        legacy_tags = [
          "method:#{env[:method]}",
          "path:#{env[:url].request_uri}",
        ]
        tags = []
        tags.concat(custom_tags(env))

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
              send_stats(legacy_tags, tags, resp, event)
            end
            resp.then(log_stats, log_stats)
          else
            event = ConcurrentFaraday::Instrumentation::Event.new
            event.start!
            resp.on_complete do
              # NOTE: This will not send stats if there was any exeception in the adapter layer
              # or any middleware after this one.
              # Faraday only provides a single on_complete callback, so we can't
              # handle errors when we are in_parallel.
              event.finish!
              send_stats(legacy_tags, tags, resp, event)
            end
          end
        else
          event = ConcurrentFaraday::Instrumentation::Event.new
          resp = nil
          begin
            resp = event.record! { @app.call(env) }
          ensure
            send_stats(legacy_tags, tags, resp, event)
          end
        end

        resp
      end

      private

      def parallel_manager(env)
        env[:parallel_manager]
      end

      def send_stats(legacy_tags, tags, resp, event)
        legacy_tags = legacy_tags.dup
        tags = tags.dup
        success = false
        availability_success = false
        ms, err = event.duration, event.exception_object

        # On errors, there should be no response.
        if resp&.status
          legacy_tags << "status:#{resp.status}"
          tags << "tripped:true" if ::GitHub::FaradayMiddleware::Resilient.tripped?(resp)
          success = resp.status < 400
          availability_success = resp.status < 500
        end

        legacy_tags << "err:#{err.class.name}" unless err.nil?
        legacy_tags << "success:#{success}"

        @dogstats.distribution("rpc.#{@service_name}.dist_time", ms, tags: legacy_tags + tags)

        @tracked_latency_slos.each do |name, target|
          latency_success = ms < target
          # Any character in the service name that's not alphanumeric, a period or underscore will be converted to an underscore
          # Example: The metric for the "github/code_scanning" catalog service will appear as "github_code_scanning.slo" in Datadog
          @dogstats.increment("#{@catalog_service}.slo", tags: ["success:#{latency_success}", "name:latency/#{name}"])
        end
        @tracked_availability_slos.each do |name|
          @dogstats.increment("#{@catalog_service}.slo", tags: ["success:#{availability_success}", "name:availability/#{name}"])
        end
      end

      def custom_tags(env)
        @custom_tags.respond_to?(:call) ? @custom_tags.call(env) : @custom_tags
      end
    end
  end
end
