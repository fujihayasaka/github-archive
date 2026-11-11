# typed: true

class AddMorePoliciesToCopilotPolicies < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)
  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :a_f, :integer, limit: 1, null: false, default: 0
      t.column :a_ft, :integer, limit: 1, null: false, default: 0
      t.column :o_f, :integer, limit: 1, null: false, default: 0
      t.column :o_ff, :integer, limit: 1, null: false, default: 0
    end
  end
end
