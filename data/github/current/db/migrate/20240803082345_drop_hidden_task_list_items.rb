class DropHiddenTaskListItems < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    drop_table :hidden_task_list_items, if_exists: true
  end

  def down
    create_table :hidden_task_list_items do |t|
      t.belongs_to :user, null: false
      t.string :removable_type, null: false, limit: 40
      t.integer :removable_id, null: false
      t.datetime :created_at, null: false, precision: 6
      t.index [:user_id, :removable_type, :removable_id], unique: true, name: "index_on_user_id_and_removable_type_and_removable_id"
    end
  end
end
