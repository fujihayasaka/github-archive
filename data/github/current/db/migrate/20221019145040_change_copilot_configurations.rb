# typed: true

class ChangeCopilotConfigurations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.remove :public_repository_telemetry
      t.remove :seat_management
      t.column :copilot_enabled, :integer, default: 0, null: false, comment:
        "Whether Copilot is enabled for this configurable (Organization or Business)"
    end
  end
end
