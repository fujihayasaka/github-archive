# typed: true
# frozen_string_literal: true

# This tracing module captures the time it takes each catalog service to respond to its portion of GraphQL Queries
# Note that this code may appear procedural compared to other code, this is intentional.  The code is attempting
# to optimize for runtime performance and reduce GC mark/sweep times by removing unnecessary object allocations.
module Platform
  module Tracing
    module FieldLatencyTracer
      include DefaultTracerBase
      # Used for testing. A hash of |catalog service name, duration| containing the time spent in each service
      attr_reader :step_by_service

      def initialize(multiplex: nil, query: nil, **kwargs)
        @query = query
        @step_by_service = {}
        super
      end

      # @param [String] catalog_service the name of the service to aggregate timings for
      # @param [Float] duration the time it took to invoke the field in seconds
      def add_step_timing_by_service(catalog_service, duration)
        @step_by_service[catalog_service] = @step_by_service.fetch(catalog_service, 0) + duration
      end

      def platform_execute
        result = super
        after_trace
        result
      end

      # This is time spent in the _initial_ resolve call, before any promises are returned.
      def execute_field(field:, query:, ast_node:, arguments:, object:)
        catalog_service, duration, result = step_timing(service: field.service_mapping) do
          super
        end

        add_step_timing_by_service(catalog_service, duration)

        result
      end

      # This is time spent calling `#sync` on returned promises.
      def execute_field_lazy(field:, query:, ast_node:, arguments:, object:)
        catalog_service, duration, result = step_timing(service: field.service_mapping) do
          super
        end
        add_step_timing_by_service(catalog_service, duration)
        result
      end

      def authorized(query:, type:, object:)
        catalog_service, duration, result = step_timing(service: type.service_mapping) do
          super
        end

        add_step_timing_by_service(catalog_service, duration)
        result
      end

      def resolve_type(query:, type:, object:)
        catalog_service, duration, result = step_timing(service: type.service_mapping) do
          super
        end

        add_step_timing_by_service(catalog_service, duration)
        result
      end

      def resolve_type_lazy(query:, type:, object:)
        catalog_service, duration, result = step_timing(service: type.service_mapping) do
          super
        end

        add_step_timing_by_service(catalog_service, duration)
        result
      end

      def execute_multiplex(multiplex:)
        # The query wasn't available in `initialize`, but it is here,
        # so we should make some recordings.
        if !@query
          @query = multiplex.queries[0]
          Platform::GlobalScope.tracers << self
        end
        super
      end

      # Wrap the block with a bunch of tracking.
      # Extracted here so it can be reused for fields and phases.
      # Given we're attempting to improve performance as well as remove GC pressure, the service name and total duration will NOT
      # be wrapped in an object that will then be immediately GC'd.
      # @param [String] service the name of the service to aggregate timings for
      #
      def step_timing(service: nil)
        # Prepare some variables so they're available outside the block below
        catalog_service = GitHub::ServiceMapping.catalog_service_name(service)

        start = get_time

        result = yield

        # Diff current allocated objects total against the initial
        total = get_time - start

        # Return the timing and the original result of `yield`
        [catalog_service, total, result]
      end

      # Returns time in seconds as a Float
      def get_time(clock: Process::CLOCK_MONOTONIC)
        Process.clock_gettime(clock)
      end

      def after_trace
        dog_tags = @query.context[:query_tracker]&.dog_tags || []

        # Since a GraphQL operation can touch multiple catalog services, we would like to track various moments of this.
        # When the request is finished, emit one metric per touched catalog service.
        @step_by_service.each do |catalog_service_name, duration|
          report_metrics(catalog_service_name, duration, dog_tags)
        end
      end

      # @param [String] catalog_service_name the name of the service to aggregate timings for
      # @param [Float] duration the time it took to invoke the field in seconds
      # @param [Array] tags the tags to be used for the metrics when emitted to DataDog
      def report_metrics(catalog_service_name, duration, tags)
        tags = tags + ["catalog_service:#{catalog_service_name}"]

        #Convert to milliseconds
        data_dog_duration = duration * 1000

        GitHub.dogstats.distribution("platform.query.dist.field.time.by_catalog_service", data_dog_duration, tags: tags)
      end

    end

  end
end
