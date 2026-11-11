# typed: true
# frozen_string_literal: true

# Action for PiperRunner that is responsible for setting a column value within a workflow
class MemexProjectWorkflowAction::SetFieldActionRunner < MemexProjectWorkflowAction::BaseActionRunner

  ACTION_TYPE = :set_field

  sig { returns(T::Array[MemexProjectItem]) }
  def run
    log_duration do
      set_field
    end
  end

  private

  sig { returns(T::Array[MemexProjectItem]) }
  def set_field
    MemexProjectWorkflow::SetFieldProcessor.run(
      input: @input,
      trigger_type: @trigger_type,
      action: @action,
      actor: @actor,
      tags: @tags + ["runner:piped"]
    )
  end
end
