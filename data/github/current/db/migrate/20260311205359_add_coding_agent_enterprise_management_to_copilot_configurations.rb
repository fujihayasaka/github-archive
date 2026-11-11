# typed: true
# frozen_string_literal: true

class AddCodingAgentEnterpriseManagementToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :coding_agent_enterprise_management, :integer, limit: 1, null: false, default: 0, comment: "Enterprise toggle to lock org admins from changing the coding_agent policy"
    end
  end
end
