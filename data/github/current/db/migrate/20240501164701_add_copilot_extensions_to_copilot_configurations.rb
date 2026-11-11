class AddCopilotExtensionsToCopilotConfigurations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :copilot_extensions, :integer, limit: 1, null: false, default: 0, comment: "The policy for allowing Copilot extensions"
    end
  end
end
