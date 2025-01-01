# typed: true

class AddNetworkIdToPushes < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    change_table :pushes, bulk: true do |t|
      t.column :network_id, :bigint, unsigned: true, null: true
      t.index :network_id
    end
  end

  def down
    change_table :pushes, bulk: true do |t|
      t.remove_index :network_id
      t.remove :network_id
    end
  end
end
