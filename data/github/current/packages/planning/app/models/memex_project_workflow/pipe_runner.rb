# typed: true
# frozen_string_literal: true

class MemexProjectWorkflow::PipeRunner
  include MemexHydroProjectAutomation::Instrumentation::PipeRunner

  def self.run(**kwargs)
    new(**T.unsafe(kwargs)).run
  end

  def initialize(workflow:, input:, actor:, event_time:, tags: [], manual_run: false)
    @workflow = workflow
    @trigger_type = workflow.trigger_type
    @input = input
    @actor = actor
    @manual_run = manual_run
    @tags = tags
    @event_time = event_time
  end

  def run
    if !@workflow.actions_valid?
      log_invalid_workflow(reason: "invalid actions")
      return
    end

    result = log_trigger_and_duration(
      type: "workflow",
      trigger_metric: METRIC_TRIGGERED,
      duration_metric: METRIC_DURATION) do
      actions = @workflow.sorted_actions
      actions.reduce(@input) do |input, action|
        # result of this becomes the next input
        MemexProjectWorkflowAction::Runner.run(
          action: action,
          input: input,
          actor: @actor,
          content_types: @workflow.content_types,
          trigger_type: @trigger_type,
          tags: @tags,
          manual_run: @manual_run)
      end
    end
    log_end_to_end_duration(@event_time) if @event_time.present?
    result
  end
end
