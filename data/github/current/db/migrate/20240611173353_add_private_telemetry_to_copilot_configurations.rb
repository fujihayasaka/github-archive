class AddPrivateTelemetryToCopilotConfigurations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :private_telemetry, :integer, limit: 1, null: false, default: 0, comment: "The policy for allowing private telemetry capture"
    end
  end
end
