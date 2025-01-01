class AddVisibilityToIntegrations < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    change_table :integrations, bulk: true do |t|
      t.column :visibility, :tinyint, null: false, default: 0, limit: 1
    end
  end
end
