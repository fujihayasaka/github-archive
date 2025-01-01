# typed: true
# frozen_string_literal: true

class AddCopilotSweAgentToConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :copilot_swe_agent, :integer, limit: 1, null: false, default: 0, comment: "Policy for Copilot SWE Agent (Project Padawan) usage"
    end
  end
end
