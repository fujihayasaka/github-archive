# typed: true
# frozen_string_literal: true

class AddAgentModeEnterpriseManagementToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :agent_mode_enterprise_management, :integer, limit: 1, null: false, default: 0, comment: "Enterprise toggle to lock org admins from changing the agent_mode policy"
    end
  end
end
