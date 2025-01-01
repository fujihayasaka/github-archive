class ArchivedRepositoryReplicas < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    drop_table :archived_repository_replicas, if_exists: true
  end
end
