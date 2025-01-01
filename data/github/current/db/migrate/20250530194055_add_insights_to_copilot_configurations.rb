# typed: true
# frozen_string_literal: true

class AddInsightsToCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :insights, :integer, limit: 1, null: false, default: 0, comment: "Policy for Insights Dashboards"
    end
  end
end
