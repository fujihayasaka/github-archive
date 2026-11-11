# typed: true

class UpdateMergeQueueEntriesToSupportSingleJobExecution < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table :merge_queue_entries, bulk: true do |t|
      # Rubocop rule got tripped and this must be done to satify it.
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
      t.change :pull_request_id, :bigint, unsigned: true
      t.change :enqueuer_id, :bigint, unsigned: true
      t.change :dequeuer_id, :bigint, unsigned: true
      t.change :merge_queue_id, :bigint, unsigned: true
      t.change :author_id, :bigint, unsigned: true

      # New columns to support the MergeQueueEntry as a FIFO queue.
      t.column :base_sha, :string, null: true, limit: 40
      t.column :head_sha, :string, null: true, limit: 40
      t.column :head_ref, :binary, null: true, limit: 1024
      t.column :attempts, :integer, null: false, default: 0
      t.column :locked, :boolean, null: false, default: false
      t.column :position, :integer, null: true
      t.column :checks_requested_at, :datetime, null: true, precision: 6

      t.index [:merge_queue_id, :locked], name: "index_merge_queue_entries_on_merge_queue_id_and_locked"
    end
  end
end
