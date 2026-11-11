# typed: true

class AddNotificationEntriesAuthorIdIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::NotificationsEntries)

  sig { void }
  def up
    add_index(:notification_entries, [:author_id], name: :index_on_author_id)
  end

  sig { void }
  def down
    remove_index(:notification_entries, name: :index_on_author_id)
  end
end
