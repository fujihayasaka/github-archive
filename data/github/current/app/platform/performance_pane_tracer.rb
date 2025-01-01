# typed: true
# frozen_string_literal: true

require "objspace"

module Platform
  # Implement the `GraphQL::Tracing` API to recording timing & external calls
  # during different query phases and during each field execution.
  module PerformancePaneTracer
    include Platform::Tracing::Helpers::BaseTraceMethods
    extend T::Helpers

    requires_ancestor { Kernel }

    def field_was_profiled?
      @detailed_profile.was_profiled?
    end

    def display_query
      DisplayQuery.new(
        tracer: self,
      )
    end

    def platform_execute
      @start_time = get_time
      initial_gc_objects = GC.stat(:total_allocated_objects)

      result = instrument { yield }

      @finish_time = get_time
      @gc_objects = GC.stat(:total_allocated_objects) - initial_gc_objects

      after_trace
      result
    end

    # This records time spent in `GraphQL::Language::Lexer`
    def lex(query_string:)
      timing, result = step_timing(name: "Lexing", path: ["Lexing"]) { super }
      @phase_timings << timing
      result
    end

    # This records time spent in `GraphQL::Language::Parser`
    def parse(query_string:)

      timing, result = step_timing(name: "Parsing", path: ["Parsing"]) { super }
      @phase_timings << timing
      result
    end

    def validate(query:, validate:)
      timing, result = step_timing(name: "Validation", path: ["Validation"]) { super }
      @phase_timings << timing
      result
    end

    # Measure all time spent in Analyzers
    def analyze_multiplex(multiplex:)
      timing, result = step_timing(name: "Analysis", path: ["Analysis"]) { super }
      @phase_timings << timing
      result
    end

    # We get all the data we need from `analyze_multiplex`,
    # so this just yields
    def analyze_query(query:)
      super
    end

    # This measure execution time before _any_ promises are returned.
    # It only makes sense  with `execute_query_lazy` times below.
    def execute_query(query:)
      @query_eager_start_time = get_time
      result = super
      @query_eager_finish_time = get_time
      result
    end

    # This measures times _after_ any Promises are returned
    # (and it includes eager and lazy time _after_ that). It only makes sense
    # with `execute_query` times above.
    def execute_query_lazy(query:, multiplex:)
      @query_lazy_start_time = get_time
      result = super
      @query_lazy_finish_time = get_time
      result
    end

    # This is time spent in the _initial_ resolve call, before any promises are returned.
    def execute_field(field:, query:, ast_node:, arguments:, object:)
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
      path = query.context[:current_path]
      name = "#{field.owner.graphql_name}.#{field.name}"
      timing, result = step_timing(path: path, name: name, lazy: true, service: field.service_mapping) do
        super
      end
      @step_timings << timing
      result
    end

    # Set a bunch of ivars of aggregate stats.
    # @return [void]
    def after_trace
      @duration = @finish_time - @start_time

      @step_timings.sort_by!(&:start_offset)
      @step_duration = @step_timings.reduce(0) { |memo, item| memo + item.duration }

      # `@duration` includes some platform setup, this is only GraphQL time:
      @graphql_duration = @graphql_finish_time - @graphql_start_time
      @platform_setup_duration = @graphql_start_time - @start_time
      @platform_teardown_duration = @finish_time - @graphql_finish_time

      # If there was an error, these might not have been initialized:
      @query_eager_start_time ||= @graphql_start_time
      @query_eager_finish_time ||= @query_eager_start_time

      # Merge eager & lazy times into `query_duration`
      query_eager_duration = @query_eager_finish_time - @query_eager_start_time
      query_lazy_duration = @query_lazy_finish_time - @query_lazy_start_time
      @query_duration = query_eager_duration + query_lazy_duration
      # Make sure we don't accidentally record stuff _after_ this:
      freeze
    end
  end
end
