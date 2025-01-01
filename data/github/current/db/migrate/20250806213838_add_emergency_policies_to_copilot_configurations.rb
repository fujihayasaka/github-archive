# typed: true

class AddEmergencyPoliciesToCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :emergency_model_1, :integer, limit: 1, null: false, default: 0
      t.column :emergency_model_2, :integer, limit: 1, null: false, default: 0
      t.column :emergency_model_3, :integer, limit: 1, null: false, default: 0
    end
  end
end
