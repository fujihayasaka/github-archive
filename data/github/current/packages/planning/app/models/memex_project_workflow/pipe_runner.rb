# typed: strict
# frozen_string_literal: true

class MemexProjectWorkflow::PipeRunner
  METRIC_PREFIX = "memex.project_workflow_runner"
  WORKFLOW_RUN_TRIGGERED_METRIC = T.let("#{METRIC_PREFIX}.workflow_run_triggered", String)
  WORKFLOW_RUN_DURATION_METRIC = T.let("#{METRIC_PREFIX}.workflow_run_duration.ms", String)
  INVALID_WORKFLOW_METRIC = T.let("#{METRIC_PREFIX}.workflow_run_invalid_workflow", String)
  AUTOMATION_DURATION_METRIC = T.let("#{METRIC_PREFIX}.workflow_run_end_to_end_duration.ms", String)

  sig { returns(MemexProjectWorkflow) }
  attr_reader :workflow

  sig { returns(T.nilable(T::Array[T.any(MemexProjectItem, Issue, PullRequest, DraftIssue)])) }
  attr_reader :input

  sig { returns(T.nilable(User)) }
  attr_reader :actor

  sig { returns(T.nilable(Time)) }
  attr_reader :event_time

  sig { returns(T::Array[String]) }
  attr_reader :tags

  sig { returns(T::Hash[String, T.untyped]) }
  attr_reader :log_attributes

  sig do
    params(
      workflow: MemexProjectWorkflow,
      input: T.nilable(T::Array[T.any(MemexProjectItem, Issue, PullRequest, DraftIssue)]),
      actor: T.nilable(User),
      event_time: T.nilable(Time),
      manual_run: T::Boolean,
      tags: T::Array[String],
      additional_log_attributes: T::Hash[String, T.untyped],
    )
    .void
  end
  def initialize(
    workflow:,
    input:,
    actor:,
    event_time: nil,
    manual_run: false,
    tags: [],
    additional_log_attributes: {})

    @workflow = workflow
    @input = input
    @actor = actor
    @event_time = event_time
    @manual_run = manual_run
    @tags = T.let(default_tags + tags, T::Array[String])
    @log_attributes = T.let(base_log_attributes.merge(additional_log_attributes), T::Hash[String, T.untyped])
  end

  sig { returns(T.anything) }
  def run
    return unless valid_workflow?

    GitHub.dogstats.increment(WORKFLOW_RUN_TRIGGERED_METRIC, tags:)
    GitHub.logger.info("Starting workflow run", **log_attributes)

    result = measure_time_elapsed do
      # We use `reduce` here because the result of each iteration of the loop becomes the next input.
      workflow.sorted_actions.reduce(@input) do |input, action|
        MemexProjectWorkflowAction::Runner.run(
          action:,
          input:,
          actor:,
          tags:,
          trigger_type: workflow.trigger_type,
          content_types: workflow.content_types,
          manual_run: manual_run?
        )
      end
    end

    GitHub.logger.info("Completed workflow run", **log_attributes)

    if event_time.present?
      GitHub.dogstats.distribution(AUTOMATION_DURATION_METRIC, GitHub::Dogstats.duration(event_time), tags:)
      GitHub.logger.info("Completed workflow automation end-to-end", **log_attributes)
    end

    result
  end

  sig { returns(T::Boolean) }
  private def valid_workflow?
    return true if @workflow.actions_valid?

    GitHub.dogstats.increment(INVALID_WORKFLOW_METRIC, tags:)
    GitHub.logger.info("Aborting execution of invalid workflow", **log_attributes)

    false
  end

  sig { params(block: T.proc.returns(T.anything)).returns(T.anything) }
  private def measure_time_elapsed(&block)
    start_time = GitHub::Dogstats.monotonic_time
    result = yield
    GitHub.dogstats.distribution(WORKFLOW_RUN_DURATION_METRIC, GitHub::Dogstats.duration(start_time), tags:)
    result
  end

  sig { returns(T::Boolean) }
  private def manual_run? = @manual_run

  sig { returns(T::Hash[String, T.untyped]) }
  private def base_log_attributes
    {
      "code.namespace": self.class.name,
      "gh.actor.id": actor&.id,
      "gh.memex.automation.input": input&.map { |item| [item.class.name, item.id] },
      "gh.memex.automation.manual_run": manual_run?,
      "gh.memex.project.id": workflow.memex_project_id,
      "gh.memex.workflow.id": workflow.id,
      "gh.memex.workflow.trigger_type": workflow.trigger_type,
      "gh.memex.workflow.actions": workflow.actions.map { |action| [action.id, action.action_type] },
    }
  end

  sig { returns(T::Array[String]) }
  private def default_tags
    [
      "trigger_type:#{workflow.trigger_type}",
      "manual_run:#{manual_run?}",
      "runner:piped",
    ]
  end
end
