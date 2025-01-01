# typed: false
# frozen_string_literal: true

module Platform
  module Tracing
    module Helpers
      module BaseTraceMethods
        # Used in a few spots when nothing was profiled:
        NO_PROFILE = {}.freeze

        # Durations are in seconds
        # Total duration:
        attr_reader :duration
        # Total objects allocated:
        attr_reader :gc_objects
        # Duration of each phase:
        attr_reader :lexing_duration, :parsing_duration, :validation_duration,
          :analysis_duration, :query_duration, :platform_setup_duration, :platform_teardown_duration
        # Field, authorize, and resolve_type times:
        attr_reader :step_timings, :step_duration
        # Phase times
        attr_reader :phase_timings
        # @return [GraphQL::Query] The query we're tracing
        attr_reader :query

        attr_reader :field_profile_path, :field_profile_type

        def initialize(field_profile_path: nil, field_profile_type: nil, track_n_plus_one: true, **kwargs)
          @trace_calls = 0
          @phase_timings = []
          @step_timings = []
          @track_n_plus_one = track_n_plus_one
          # Prepare the profile object, massaging some input:
          @detailed_profile = Platform::PerformancePaneTracer::DetailedProfile.new(
            profile_path: field_profile_path ? field_profile_path.split(".") : [],
            profile_type: field_profile_type,
          )
          @field_profile_path = field_profile_path
          @field_profile_type = field_profile_type
          # Initialize the external call diff, so we can track external calls
          # during resolution
          @external_call_diff = Platform::PerformancePaneTracer::ExternalCallDiff.new
          super
        end

        def authorized(query:, type:, object:)
          name = "#{type.graphql_name}.authorized?"
          path = [name]
          path = query.context[:current_path] + [name] if query.context[:current_path].present?
          gql_path = query.context[:current_path]

          timing, result = step_timing(path: path, name: name, gql_path: gql_path, lazy: false, service: type.service_mapping) do
            super
          end
          @step_timings << timing
          result
        end

        def authorized_lazy(query:, type:, object:)
          name = "#{type.graphql_name}.authorized?"
          path = [name]
          path = query.context[:current_path] + [name] if query.context[:current_path].present?
          gql_path = query.context[:current_path]

          timing, result = step_timing(path: path, name: name, gql_path: gql_path, lazy: true, service: type.service_mapping) do
            super
          end
          @step_timings << timing
          result
        end

        def resolve_type(query:, type:, object:)
          name = "#{type.graphql_name}.resolve_type"
          path = [name]
          path = query.context[:current_path] + [name] if query.context[:current_path].present?
          gql_path = query.context[:current_path]
          timing, result = step_timing(path: path, name: name, gql_path: gql_path, lazy: false, service: type.service_mapping) do
            super
          end
          @step_timings << timing
          result
        end

        def resolve_type_lazy(query:, type:, object:)
          name = "#{type.graphql_name}.resolve_type"
          path = [name]
          path = query.context[:current_path] + [name] if query.context[:current_path].present?
          gql_path = query.context[:current_path]
          timing, result = step_timing(path: path, name: name, gql_path: gql_path, lazy: false, service: type.service_mapping) do
            super
          end
          @step_timings << timing
          result
        end

        def execute_multiplex(multiplex:)
          # The query wasn't available in `initialize`, but it is here,
          # so we should make some recordings.
          if !@query
            @query = multiplex.queries[0]
            # This wasn't available when the profile was initialized, so add it now.
            @detailed_profile.query = @query
            Platform::GlobalScope.tracers << self
          end
          @graphql_start_time ||= get_time
          result = super
          @graphql_finish_time = get_time
          result
        end

        # Wrap the block with a bunch of tracking.
        # Extracted here so it can be reused for fields and phases.
        def step_timing(name:, path:, lazy: false, service: nil, gql_path: nil)
          # Prepare some variables so they're available outside the block below
          start = nil
          total = nil
          cpu_start = nil
          cpu_total = nil
          allocated_objects_count = 0
          catalog_service = GitHub::ServiceMapping.catalog_service_name(service)
          @external_call_diff.start

          result, allocated_objects, lines = @detailed_profile.with_detailed_profile(path) do
            # Get starting time (wall clock & CPU time)
            start = get_time
            cpu_start = get_time(clock: Process::CLOCK_PROCESS_CPUTIME_ID)
            # See how many objects were _previously_ allocated
            initial_objects_count = GC.stat(:total_allocated_objects)
            res = yield
            # Diff current CPU time against the start time
            cpu_total = get_time(clock: Process::CLOCK_PROCESS_CPUTIME_ID) - cpu_start
            # Diff current wall clock time against start
            total = get_time - start
            # Diff current allocated objects total against the initial
            allocated_objects_count = GC.stat(:total_allocated_objects) - initial_objects_count
            res
          end

          # Read the changes since our last diff
          stats_diff = @external_call_diff.stop
          # Add some local measurements to the array of results
          stats_diff << cpu_total << allocated_objects << allocated_objects_count << lines

          # Capture everything in a timing object
          timing = Platform::PerformancePaneTracer::StepTiming.new(
            start_offset: start - @start_time,
            duration: total,
            name: name,
            path: path,
            gql_path: gql_path,
            lazy: lazy,
            stats: stats_diff,
            catalog_service: catalog_service
          )

          # Return the timing and the original result of `yield`
          [timing, result]
        end

        # Returns time in seconds
        def get_time(clock: Process::CLOCK_MONOTONIC)
          Process.clock_gettime(clock)
        end

        def track_mysql
          GitHub::MysqlInstrumenter.with_track(skip: @track_n_plus_one ? [] : [:backtrace, :tags, :digested_sql]) do
            yield
          end
        end

        def track_query_cache
          # We don't use cached queries to calculate N+1, so we can always skip expensive fields.
          QueryCacheLogSubscriber.with_track(skip: [:backtrace, :tags, :digested_sql]) do
            yield
          end
        end

        def instrument
          result = nil

          GitRPCLogSubscriber.with_track do
            track_mysql do
              track_query_cache do
                previous_redis_track = Redis::Client.track
                previous_es_track = Elastomer::QueryStats.instance.track
                begin
                  Redis::Client.track = true
                  Elastomer::QueryStats.instance.track = true
                  result = yield
                ensure
                  Redis::Client.track = previous_redis_track
                  Elastomer::QueryStats.instance.track = previous_es_track
                end
              end
            end
          end

          result
        end

      end
    end
  end
end
