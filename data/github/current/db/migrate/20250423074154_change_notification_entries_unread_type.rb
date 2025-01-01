# typed: strict
# frozen_string_literal: true

class ChangeNotificationEntriesUnreadType < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::NotificationsEntries)

  sig { void }
  def up
    change_column :notification_entries, :unread, :smallint, default: 1
  end

  sig { void }
  def down
    change_column :notification_entries, :unread, :tinyint, limit: 1, default: 1
  end
end
