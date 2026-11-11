# typed: true
# frozen_string_literal: true

class MigrateMergeQueueEntriesForSha256 < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :merge_queue_entries, bulk: true do |t|
      t.change :base_sha, :string, limit: 64, null: true
      t.change :head_sha, :string, limit: 64, null: true
      t.change :enqueued_head_sha, :string, limit: 64, null: true
    end
  end

  def down
    change_table :merge_queue_entries, bulk: true do |t|
      t.change :base_sha, :string, limit: 40, null: true
      t.change :head_sha, :string, limit: 40, null: true
      t.change :enqueued_head_sha, :string, limit: 40, null: true
    end
  end
end
