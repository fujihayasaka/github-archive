# typed: true
class NotificationEntriesUserIdAndListIdUpdate < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::NotificationsEntries)

  def up
    change_table :notification_entries, bulk: true do |t|
      t.change  :id, :bigint, unsigned: true, null: false
      t.change  :user_id, :bigint, unsigned: true, null: false
      t.change  :list_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :notification_entries, bulk: true do |t|
      t.change  :id, :integer, null: false
      t.change  :user_id, :integer, null: false
      t.change  :list_id, :integer, null: false
    end
  end
end
