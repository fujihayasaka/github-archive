class GlobalNoticesLastCheckedAtIndex < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table :global_notices, bulk: true do |t|
      t.remove_index :last_checked_at, name: "index_global_notices_on_last_checked_at"
      t.index [:user_id, :last_checked_at, :name], unique: false, name: "index_global_notices_on_user_id_last_checked_at_and_name"
    end
  end
end
