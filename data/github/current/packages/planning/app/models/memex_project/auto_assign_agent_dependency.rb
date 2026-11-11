# typed: strict
# frozen_string_literal: true

module MemexProject::AutoAssignAgentDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { MemexProject }

  sig { returns(T::Boolean) }
  def auto_assign_agent_enabled?
    workflows.where(trigger_type: :auto_assign_agent, enabled: true).exists?
  end

  sig { params(enabled: T::Boolean, updater: User, number: T.nilable(Integer)).void }
  def toggle_auto_assign_agent!(enabled:, updater:, number: nil)
    scope = workflows.where(trigger_type: :auto_assign_agent)
    scope = scope.where(number: number) if number

    workflows_affected_count = scope.update_all(enabled: enabled, last_updater_id: updater.id)

    ensure_agent_workflow_states!(scope) if enabled

    GitHub.dogstats.gauge(
      "memex.auto_assign_agent_workflows_affected.count",
      workflows_affected_count,
      tags: [
        "enabled:#{enabled}",
      ]
    )
  end

  private

  # Creates MemexProjectAgentWorkflowState rows for any assign_copilot actions
  # that don't already have one.
  sig { params(workflow_scope: ActiveRecord::Relation).void }
  def ensure_agent_workflow_states!(workflow_scope)
    workflow_scope.includes(actions: :agent_workflow_state).find_each do |workflow|
      workflow.actions.each do |action|
        next unless action.assign_copilot?
        next if action.agent_workflow_state.present?

        action.create_agent_workflow_state!(
          concurrency_limit: MemexProjectAgentWorkflowState::DEFAULT_CONCURRENCY_LIMIT
        )
      end
    end
  end
end
