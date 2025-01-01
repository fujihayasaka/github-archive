# typed: true

class AddIsAlphanumericToKeyLinks < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    change_table :key_links, bulk: true do |t|
      t.column :is_alphanumeric, :boolean, default: true, null: false
      t.change :id, :bigint, unsigned: true
      t.change :owner_id, :bigint, unsigned: true
    end
  end
end
