# typed: true
# frozen_string_literal: true

class AddCopilotUsageRecordsToCopilotConfigurations < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :copilot_usage_records_api, :integer, limit: 1, null: false, default: 0,
        comment: "If enabled, Enterprises will be able to view their members Copilot Usage Records via API"
      t.column :copilot_usage_records_streaming, :integer, limit: 1, null: false, default: 0,
        comment: "If enabled, Enterprises will be able to view their members Copilot Usage Records via streaming"
    end
  end
end
