# typed: true

class AddNumberToCustomCopilots < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::Copilot

  def up
    change_table :custom_copilots, bulk: true do |t|
      t.column :number, :bigint, unsigned: true, null: true
      t.index [:owner_id, :owner_type, :number], unique: true, name: "index_custom_copilots_owner_number"
    end
  end

  def down
    change_table :custom_copilots, bulk: true do |t|
      t.remove_index name: "index_custom_copilots_owner_number"
      t.remove :number
    end
  end
end
