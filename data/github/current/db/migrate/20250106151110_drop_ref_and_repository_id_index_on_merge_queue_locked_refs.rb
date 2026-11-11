# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration
# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class DropRefAndRepositoryIdIndexOnMergeQueueLockedRefs < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    change_table :merge_queue_locked_refs, bulk: true do |t|
      t.remove_index name: "index_merge_queue_locked_refs_on_repository_id_and_ref"
    end
  end

  def down
    change_table :merge_queue_locked_refs, bulk: true do |t|
      t.index [:repository_id, :ref], name: "index_merge_queue_locked_refs_on_repository_id_and_ref", unique: true
    end
  end
end
