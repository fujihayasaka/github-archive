# typed: true

class DropRepositoryPendingDeletions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    drop_table :repository_pending_deletions, if_exists: true
  end
end
