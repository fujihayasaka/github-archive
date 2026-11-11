# typed: true
# frozen_string_literal: true

class AddIndexOnRefForMergeQueueLockedRefs < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    add_index :merge_queue_locked_refs, :ref
  end
end
