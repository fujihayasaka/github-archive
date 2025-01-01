# typed: true
# frozen_string_literal: true

class RenameSweAgentColumnInCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def up
    change_table :copilot_configurations, bulk: true do |t|
      t.column :swe_agent, :integer, limit: 1, null: false, default: 0, comment: "Policy for Copilot SWE Agent usage"
      t.remove :copilot_swe_agent
    end
  end

  def down
    change_table :copilot_configurations, bulk: true do |t|
      t.column :copilot_swe_agent, :integer, limit: 1, null: false, default: 0, comment: "Policy for Copilot SWE Agent usage"
      t.remove :swe_agent
    end
  end
end
