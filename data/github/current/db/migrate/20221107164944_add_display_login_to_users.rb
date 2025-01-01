# typed: true
class AddDisplayLoginToUsers < ActiveRecord::Migration[7.1]
  def change
    change_table :users, bulk: true do |t|
      t.column :display_login, "varchar(40)", null: true
      t.index [:display_login, :business_id], name: "index_on_display_login_and_business_id", unique: true

      t.change :id, :bigint, unsigned: true
      t.change :last_read_broadcast_id, :bigint, unsigned: true
      t.change :primary_language_name_id, :bigint, unsigned: true
      t.change :migration_id, :bigint, unsigned: true
    end
  end
end
