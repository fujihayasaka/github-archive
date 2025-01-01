# typed: true
# frozen_string_literal: true

module MemexHydroProjectAutomation
  module Instrumentation
    module Shared
      extend T::Helpers

      requires_ancestor { Object }

      METRIC_PREFIX = "memex.project_workflow_runner"

      # Log and stat the trigger and duration of a unit of work.
      # This is a generic method used for tracking complete workflow and individual action runs.
      #
      # type - String - the type of unit of work
      # trigger_metric - String - the metric to increment when the unit of work is triggered
      # duration_metric - String - the distribution metric to log when the unit of work is completed
      # extra - Hash - any key => val params to include in the log message
      # block - Proc - the block to run to calculate the duration
      #
      # Returns result of block
      def log_trigger_and_duration(type:, trigger_metric:, duration_metric:, **extra, &block)
        # The T.bind indicates that this module could be included arbitrarily, but this method must only be used by these modules/classes
        T.bind(self, T.any(MemexProjectWorkflow::PipeRunner, MemexProjectWorkflowAction::BaseActionRunner))
        context = log_payload.merge(extra)
        GitHub.dogstats.increment(trigger_metric, tags: stats_tags_default)
        log("Triggered #{type.upcase} run with the following context: #{context.inspect}")

        start_time = GitHub::Dogstats.monotonic_time
        result = yield
        elapsed = GitHub::Dogstats.duration(start_time)
        GitHub.dogstats.distribution(duration_metric, elapsed, tags: stats_tags_default)
        log("Completed #{type.upcase} run in #{elapsed}ms: #{context.inspect}")
        result
      end

      # Log conditionally based on environment.
      #
      # msg - String
      #
      # Returns nothing
      def log(msg)
        if Rails.env.development?
          Rails.logger.debug("#{self.class.name}: #{msg}")
        else
          GitHub.logger.info(
            msg,
            "code.namespace": self.class.name,
            "gh.actor.id": @actor&.id,
            "gh.memex.automation.trigger_type": @trigger_type,
          )
        end
      end
    end
  end
end
