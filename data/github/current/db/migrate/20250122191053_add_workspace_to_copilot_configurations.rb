# typed: true
# frozen_string_literal: true

class AddWorkspaceToCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :workspace_for_emu, :integer, limit: 1, null: false, default: 0, comment: "The policy for allowing Copilot Workspace for EMUs"
    end
  end
end
