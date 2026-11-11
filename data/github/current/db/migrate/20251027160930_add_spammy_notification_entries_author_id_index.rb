# typed: true

class AddSpammyNotificationEntriesAuthorIdIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::NotificationsEntries)

  sig { void }
  def up
    add_index(:spammy_notification_entries, [:author_id], name: :index_on_author_id)
  end

  sig { void }
  def down
    remove_index(:spammy_notification_entries, name: :index_on_author_id)
  end
end
