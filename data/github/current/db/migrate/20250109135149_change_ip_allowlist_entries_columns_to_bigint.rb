# typed: true

class ChangeIpAllowlistEntriesColumnsToBigint < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :ip_allowlist_entries, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false
      t.change :owner_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :ip_allowlist_entries, bulk: true do |t|
      t.change :id, :int, null: false
      t.change :owner_id, :int, null: false
    end
  end
end
