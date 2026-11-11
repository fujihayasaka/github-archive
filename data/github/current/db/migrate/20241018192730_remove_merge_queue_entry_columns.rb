# typed: true

class RemoveMergeQueueEntryColumns < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table :merge_queue_entries, bulk: true do |t|
      t.remove :dequeuer_id
      t.remove :dequeued_at
      t.remove :deploy_started_at
    end
  end
end
