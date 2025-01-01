class AddUsageMetricsApiSettingToCopilotConfiguration < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :usage_telemetry_api, :integer, limit: 1, null: false, default: 0
    end
  end
end
