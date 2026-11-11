# typed: true

class AddModelPoliciesToCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :model_policies, :json, null: true
    end
  end
end
