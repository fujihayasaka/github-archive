# typed: true
# frozen_string_literal: true

module Platform
  module PerformancePaneTracer
    # This is the top-level entry in the tree view in the staff performance bar.
    #
    # When it's initialized, it takes the list of timings and restructures them
    # into a tree. Then, after the tree is built, it uses `DisplayStep#freeze_stats`
    # to calculate aggregates and freeze elements in the tree.
    # (`.freeze` is just to be sure that nothing gets added later by mistake.)
    #
    # It's rendered into `app/views/site/_graphql_stats_query.html.erb`.
    class DisplayQuery
      def initialize(tracer:)
        @tracer = tracer
        @name = tracer.query.selected_operation_name
        @path = [@name]

        # Prepare this phase so we can populate it with field resolution timings
        execution_phase = prepare_phase("Execution", @tracer.query_duration)

        # Restructure the `step_timings` array into a tree,
        # using `t.path` to determine where the timings belong
        tracer.step_timings.each do |t|
          child_node = execution_phase
          child_path = [name]
          t.path.each_with_index do |path_part|
            if path_part.is_a?(String)
              child_path << path_part
              child_node = child_node.children[path_part] ||= DisplayStep.new(name: path_part, path: child_path)
            end
          end
          child_node.timings << t
        end

        @count = 1
        @total_ms = @tracer.duration * 1000.0
        @field_names = [@tracer.query.selected_operation.operation_type]

        # Prepare the phases for rendering:
        @children = [
          prepare_phase("Platform Setup", @tracer.platform_setup_duration),
          prepare_step("Lexing"),
          prepare_step("Parsing"),
          prepare_step("Validation"),
          prepare_step("Analysis"),
          execution_phase,
          prepare_phase("Platform Teardown", @tracer.platform_teardown_duration),
        ]

        @children.map(&:freeze_stats)
        # Figure out how much unaccounted time there was
        overhead_time_seconds = (@total_ms - @children.sum(&:total_ms)) / 1000
        overhead_phase = prepare_phase("Unaccounted/Overhead", overhead_time_seconds)
        overhead_phase.freeze_stats
        @children << overhead_phase

        @children_ms = @children.sum(&:total_ms)
        # This _should_ be `0` since unaccounted time has its own entry
        @own_ms = @total_ms - @children_ms
      end

      attr_reader :tracer, :name, :path, :children, :count, :field_names
      attr_reader :total_ms, :children_ms, :own_ms

      def total_allocated_objects
        @tracer.gc_objects
      end

      private

      def prepare_phase(name, duration_s)
        DisplayPhase.new(
          name: name,
          path: [@name, name],
          total_ms: duration_s * 1000
        )
      end

      def prepare_step(name)
        step_timing = @tracer.phase_timings.find { |t| t.name == name }
        timings = step_timing ? [step_timing] : []
        # Use a DisplayStep for more detailed info
        DisplayStep.new(name: name, path: [@name, name], timings: timings)
      end
    end
  end
end
