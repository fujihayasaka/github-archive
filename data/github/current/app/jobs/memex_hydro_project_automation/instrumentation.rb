# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module MemexHydroProjectAutomation

  module Instrumentation
    extend T::Helpers
    requires_ancestor { HydroMessageJob }

    STATS_PREFIX = "memex.hydro_job_processing"
    METRIC_SKIPPED_MESSAGE = "#{STATS_PREFIX}.message_skipped"
    METRIC_MATCHED_MESSAGE = "#{STATS_PREFIX}.message_matched"
    METRIC_ENQUEUED_MESSAGE = "#{STATS_PREFIX}.workflow_run_enqueued"
    METRIC_SUCCESS = "#{STATS_PREFIX}.success"

    SKIP_REASON_DISABLED = "feature flag disabled"
    SKIP_REASON_NO_MATCHES = "no matching memexes"
    SKIP_REASON_NO_WORKFLOWS = "no matching workflows"
    SKIP_REASON_AUTOMATIONS_DISABLED = "automations disabled"
    SKIP_REASON_KILL_SWITCH_ENABLED = "kill switch enabled"
    SKIP_REASON_MISSING_REQUIRED_DATA = "required data is missing"

    # Provide standard tags that we want to capture from every message,
    # regardless of the metric.
    #
    # message - Object<HydroConsumerMessage>
    #
    # Returns Array
    def stats_tags_default
      [
        "topic:#{topic}",
        "queue:#{queue}"
      ]
    end

    def skip_disabled
      skip(SKIP_REASON_DISABLED)
    end

    def skip_no_matches
      skip(SKIP_REASON_NO_MATCHES)
    end

    def skip_no_workflows
      skip(SKIP_REASON_NO_WORKFLOWS)
    end

    def skip_automations_disabled
      skip(SKIP_REASON_AUTOMATIONS_DISABLED)
    end

    def skip_kill_switch_enabled
      skip(SKIP_REASON_KILL_SWITCH_ENABLED)
    end

    def skip_missing_required_data
      skip(SKIP_REASON_MISSING_REQUIRED_DATA)
    end

    # Encapsulate the various logging/stats logic that we want to execute
    # anytime a message is skipped. NOTE: Since reason will be converted to tags,
    # its value should always be static in order to prevent cardinality explosions.
    # See https://git.io/J3Ej8 for more.
    #
    # reason - String
    #
    # Returns nil
    def skip(reason)
      tags = ["reason:#{reason}"] + stats_tags_default
      GitHub.dogstats.increment(METRIC_SKIPPED_MESSAGE, tags: tags)
    end

    def log_topic
      log(
        "Processing memex project automation message",
        "gh.memex.automation.status" => "processing-message"
      )
    end

    # Log that we have found workflows matching the content and will attempt to run
    # workflows for it.
    #
    # content_id - Integer
    # content_type - String
    # workflows - Array<MemexProjectWorkflow>
    # actor - User
    #
    # Returns nothing
    def log_workflows(content_id:, content_type: "unknown", workflows: [], actor: User.ghost)
      GitHub.dogstats.increment(METRIC_MATCHED_MESSAGE, tags: stats_tags_default + ["runner:piped"])
      log(
        "Executing memex project automation workflows",
        "gh.actor.id" => actor.id,
        "gh.memex.automation.content_type" => content_type,
        "gh.memex.automation.content_id" => content_id,
        "gh.memex.automation.workflow_ids" => workflows.map(&:id).inspect,
        "gh.memex.automation.status" => "executing-runner"
      )
    end

    # Log that we are enqueueing a workflow run
    #
    # workflow - MemexProjectWorkflow
    # input - Array<Tuple<content_type, content_id>>
    # actor - User
    #
    # Returns nothing
    def log_workflow_enqueued(workflow:, input:, actor: User.ghost)
      GitHub.dogstats.increment(METRIC_ENQUEUED_MESSAGE, tags: stats_tags_default + ["runner:piped", "trigger_type:#{workflow.trigger_type}"])
      log(
        "Enqueueing memex project automation workflow",
        "gh.actor.id" => actor.id,
        "gh.memex.automation.workflow_id" => workflow.id,
        "gh.memex.automation.input" => input.inspect,
        "gh.memex.automation.status" => "executing-runner"
      )
    end

    # Log and stat full stack execution without error
    #
    # Returns nothing
    def log_success
      GitHub.dogstats.increment(METRIC_SUCCESS, tags: stats_tags_default)
      log(
        "Successfully completed memex automation workflow",
        "gh.memex.automation.status" => "processing-complete"
      )
    end

    # Convenience method for pulling as many log facets off the instance as
    # possible
    #
    # Returns hash
    def log_hash
      {
        "code.namespace" => self.class.name,
        "gh.job.queue" => queue,
        "messaging.kafka.source.topic" => topic,
        "messaging.kafka.source.partition" => partition,
        "messaging.kafka.message.schema" => schema,
        "messaging.kafka.message.offset" => offset,
        "messaging.kafka.message.timestamp" => timestamp
      }
    end

    # Log conditionally based on environment
    #
    # msg - String
    #
    # Returns nothing
    def log(msg, args = {})
      if Rails.env.development?
        Rails.logger.debug("#{self.class.name}: #{msg}")
      else
        GitHub.logger.info(msg, log_hash.merge(args))
      end
    end
  end
end
