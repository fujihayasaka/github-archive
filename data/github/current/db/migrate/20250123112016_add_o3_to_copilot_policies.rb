# typed: true

class AddO3ToCopilotPolicies < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :o3, :integer, limit: 1, null: false, default: 0
    end
  end
end
