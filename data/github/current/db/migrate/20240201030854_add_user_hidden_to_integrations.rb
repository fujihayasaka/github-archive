class AddUserHiddenToIntegrations < ActiveRecord::Migration[7.2]
  def up
    change_table :integrations, bulk: true do |t|
      t.boolean :user_hidden, null: false, default: false
      t.index [:user_hidden, :owner_id, :owner_type], name: "index_user_hidden_and_owner_id_and_owner_type"
    end
  end

  def down
    change_table :integrations, bulk: true do |t|
      t.remove :user_hidden
      t.remove_index [:user_hidden, :owner_id, :owner_type], name: "index_user_hidden_and_owner_id_and_owner_type"
    end
  end
end
