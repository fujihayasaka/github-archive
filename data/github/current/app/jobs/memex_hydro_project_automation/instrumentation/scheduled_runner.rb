# typed: true
# frozen_string_literal: true

module MemexHydroProjectAutomation
  module Instrumentation
    module ScheduledRunner
      include MemexHydroProjectAutomation::Instrumentation::Shared

      METRIC_MATCHED = "#{METRIC_PREFIX}.scheduled_runner_workflows_matched"
      METRIC_ENQUEUED = "#{METRIC_PREFIX}.scheduled_runner_workflow_enqueued"

      def stats_tags_default
        T.bind(self, ApplicationJob)
        [
          "runner:piped",
          "queue:#{queue_name}",
        ]
      end

      # Log that we have found workflows matching the schedule conditions and will attempt to run
      # workflows for it.
      #
      # workflows - Array<MemexProjectWorkflow>
      # actor - User
      #
      # Returns nothing
      def log_workflows_matched(workflows: [], actor: User.ghost)
        GitHub.dogstats.increment(METRIC_MATCHED, tags: stats_tags_default)
        log("Found matching workflows: #{workflows.map(&:id).inspect}. Running workflows for actor id: #{actor.id}")
      end

      # Log that we are enqueueing a workflow run
      #
      # workflow - MemexProjectWorkflow
      # input - Array<Tuple<content_type, content_id>>
      # actor - User
      #
      # Returns nothing
      def log_workflow_enqueued(workflow:, input:, actor: User.ghost)
        GitHub.dogstats.increment(METRIC_ENQUEUED, tags: stats_tags_default + ["trigger_type:#{workflow.trigger_type}"])
        log("Enqueued workflow with id #{workflow.id} with input #{input.inspect}. Running workflows for actor id: #{actor.id}")
      end
    end
  end
end
