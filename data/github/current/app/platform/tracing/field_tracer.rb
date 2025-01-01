# typed: false
# frozen_string_literal: true

module Platform
  module Tracing
    module FieldTracer
      MAX_TRACE_CALLS = 10_000
      include Platform::Tracing::Helpers::BaseTraceMethods

      def platform_execute
        @start_time = get_time
        initial_gc_objects = GC.stat(:total_allocated_objects)

        result = instrument { yield }

        @finish_time = get_time
        @gc_objects = GC.stat(:total_allocated_objects) - initial_gc_objects

        after_trace
        result
      end

      # This is time spent in the _initial_ resolve call, before any promises are returned.
      def execute_field(field:, query:, ast_node:, arguments:, object:)
        @trace_calls += 1

        return super if @trace_calls > MAX_TRACE_CALLS

        path = query.context[:current_path]
        name = "#{field.owner.graphql_name}.#{field.name}"
        timing, result = step_timing(path: path, name: name, service: field.service_mapping) do
          super
        end
        @step_timings << timing
        result
      end

      # This is time spent calling `#sync` on returned promises.
      def execute_field_lazy(field:, query:, ast_node:, arguments:, object:)
        @trace_calls += 1

        return super if @trace_calls > MAX_TRACE_CALLS

        path = query.context[:current_path]
        name = "#{field.owner.graphql_name}.#{field.name}"
        timing, result = step_timing(path: path, name: name, lazy: true, service: field.service_mapping) do
          super
        end
        @step_timings << timing
        result
      end

      def after_trace
        exceeded_max_trace_calls = @trace_calls > MAX_TRACE_CALLS
        dog_tags = @query.context[:query_tracker]&.dog_tags || []
        GitHub.dogstats.distribution("platform.query.field_tracer.trace_calls", @trace_calls, tags: dog_tags + ["exceeded_max_trace_calls:#{exceeded_max_trace_calls}"])

        return if exceeded_max_trace_calls

        # Since a GraphQL operation can touch multiple catalog services, we would like to track various moments of this.
        # When the request is finished, emit one metric per touched catalog service.
        @step_timings.group_by(&:catalog_service).map do |service, steps|
          Stats::CatalogService.new(service, steps, @track_n_plus_one, dog_tags).report
        end
      end
    end
  end
end
