class AddMaxSeatsToCopilotConfigurations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :max_seats, :integer, default: 0, null: false, comment: "The maximum number of seats allowed for this configurable (Organization or Business)"
    end
  end
end
