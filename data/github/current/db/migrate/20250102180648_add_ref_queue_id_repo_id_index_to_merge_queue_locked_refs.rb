# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddRefQueueIdRepoIdIndexToMergeQueueLockedRefs < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    change_table :merge_queue_locked_refs, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
      t.change :merge_queue_id, :bigint, unsigned: true
      t.index [:repository_id, :merge_queue_id, :ref], name: "index_merge_queue_locked_refs_on_repo_id_queue_id_and_ref", unique: true
    end
  end

  def down
    change_table :merge_queue_locked_refs, bulk: true do |t|
      t.change :id, :int
      t.change :repository_id, :int
      t.remove :merge_queue_id, :int
      t.remove_index name: "index_merge_queue_locked_refs_on_repo_id_queue_id_and_ref"
    end
  end
end
