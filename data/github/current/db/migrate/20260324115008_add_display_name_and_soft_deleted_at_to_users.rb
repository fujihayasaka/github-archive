# typed: true

class AddDisplayNameAndSoftDeletedAtToUsers < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Usersd)

  def change
    change_table :users, bulk: true do |t|
      t.column :display_name, :string, null: true, after: :login, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.index [:display_name], name: :index_users_on_display_name
      t.column :soft_deleted_at, :datetime, null: true, precision: 6
      t.index [:soft_deleted_at], name: :index_users_on_soft_deleted_at
    end
  end
end
