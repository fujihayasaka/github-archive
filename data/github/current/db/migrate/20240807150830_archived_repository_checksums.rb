class ArchivedRepositoryChecksums < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    drop_table :archived_repository_checksums, if_exists: true
  end
end
