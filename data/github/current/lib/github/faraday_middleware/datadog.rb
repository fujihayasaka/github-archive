# typed: true
# frozen_string_literal: true

module GitHub
  module FaradayMiddleware
    # Faraday Middleware for opentracing our Spokes client
    #
    # It would be "better" to use faraday/tracer middleware rather than write our
    # own, however  the current version doesn't support our old faraday. It's not
    # really *that* hard to build a purpose built middlware so we can just deal
    # with it.
    class Datadog < Faraday::Middleware
      # Create a new Faraday Tracer middleware.
      #
      # @param app The faraday application/middlewares stack.
      # @param service_name [String, nil] Remote service name (for some
      #        unspecified definition of "service")
      # @param catalog_service [String, nil] Catalog service name (if different from service_name)
      # @param stats Stats implementation
      # @tracked_latency_slos [Hash, nil] Latency SLO metrics to be reported to Datadog
      # @tracked_availability_slos [Array, nil] Availability SLO metrics to be reported to Datadog
      # @enable_path_tag [Boolean] Whether to include the path tag in the
      # metric. Defaults to false, as path can be a very high cardinality tag # leading to high
      # metric costs.
      def initialize(app, options = {})
        super(app)
        @service_name = options[:service_name] || "unknown"
        @catalog_service = options[:catalog_service] || @service_name
        @dogstats = options[:stats]
        @custom_tags = options[:custom_tags] || []
        @tracked_latency_slos = options[:tracked_latency_slos] || {}
        @tracked_availability_slos = options[:tracked_availability_slos] || []
        @enable_path_tag = options[:enable_path_tag] || false
      end

      def call(env)
        start = Time.now
        success = T.let(false, T::Boolean)
        availability_success = T.let(false, T::Boolean)

        tags = ["method:#{env[:method]}"]
        tags << "path:#{env[:url].request_uri}" if @enable_path_tag

        tags.concat custom_tags(env)
        begin
          @app.call(env).on_complete do
            tags << "status:#{env[:status]}"
            tags << "tripped:true" if GitHub::FaradayMiddleware::Resilient.tripped? env.response

            if env[:status] < 400
              success = true
            end
            availability_success = env[:status] < 500
          end
        rescue Exception => e # rubocop:todo Lint/RescueException
          tags << "err:#{e.class.name}"
          raise
        ensure
          tags << "success:#{success}"
          ms = (Time.now - start) * 1000

          @dogstats.distribution("rpc.#{@service_name}.dist_time", ms, tags: tags)

          tags << "service_name:#{@service_name}"

          tags.concat(GitHub.context[:remote_call_source_datadog_tags]) if GitHub.context[:remote_call_source_datadog_tags]

          @dogstats.distribution("gh.faraday_client.dist_time", ms, tags: tags)

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
      end

      private

      def custom_tags(env)
        @custom_tags.respond_to?(:call) ? @custom_tags.call(env) : @custom_tags
      end
    end
  end
end
