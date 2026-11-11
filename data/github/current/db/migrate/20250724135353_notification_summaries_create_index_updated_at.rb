# typed: true

class NotificationSummariesCreateIndexUpdatedAt < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::NotificationsSummaries)

  sig { void }
  def up
    add_index(:notification_summaries,
              [:updated_at, :id, :list_id, :list_type, :thread_key],
              name: :idx_updated_at_id_list_id_list_type_thread_key)
  end

  sig { void }
  def down
    remove_index(:notification_summaries,
                 name: :idx_updated_at_id_list_id_list_type_thread_key)
  end
end
