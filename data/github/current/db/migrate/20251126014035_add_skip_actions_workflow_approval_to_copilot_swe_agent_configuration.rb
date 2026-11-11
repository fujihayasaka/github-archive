# typed: true
# frozen_string_literal: true

class AddSkipActionsWorkflowApprovalToCopilotSweAgentConfiguration < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_swe_agent_configuration, bulk: true do |t|
      t.column :require_actions_workflow_approval_for_copilot_prs, :boolean, null: false, default: true, comment: "Whether to require human approval for workflow runs on Copilot pull requests"
    end
  end
end
