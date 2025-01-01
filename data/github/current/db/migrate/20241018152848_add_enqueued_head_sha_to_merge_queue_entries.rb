# typed: true

class AddEnqueuedHeadShaToMergeQueueEntries < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table :merge_queue_entries, bulk: true do |t|
      t.column :enqueued_head_sha, :string, null: true, limit: 40
    end
  end

end
