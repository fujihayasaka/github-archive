# typed: true

class DropUnusedIndexesFromStatuses < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::RepositoriesActionsChecks

  def change
    change_table :statuses, bulk: true do |t|
      t.remove_index [:archived_at], name: "index_statuses_on_archived_at"
      t.remove_index [:commit_oid, :repository_id, :context], name: "index_statuses_on_commit_oid_and_repository_id_and_context"
    end
  end
end
