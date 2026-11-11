# typed: true

class AddNewBreakglassPoliciesToCopilotConfigurationsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :copilot_configurations, bulk: true do |t|
      t.column :hulk, :integer, limit: 1, null: false, default: 0
      t.column :captainamerica, :integer, limit: 1, null: false, default: 0
      t.column :antman, :integer, limit: 1, null: false, default: 0
      t.column :blackpanther, :integer, limit: 1, null: false, default: 0
      t.column :wintersoldier, :integer, limit: 1, null: false, default: 0
    end
  end
end
