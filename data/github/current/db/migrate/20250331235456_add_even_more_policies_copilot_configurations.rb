# typed: true

class AddEvenMorePoliciesCopilotConfigurations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :o_t, :integer, limit: 1, null: false, default: 0
      t.column :o_fm, :integer, limit: 1, null: false, default: 0
    end
  end
end
