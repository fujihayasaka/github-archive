# typed: strict

class DropSharedStorageArtifactEvents < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  sig { void }
  def change
    drop_table :shared_storage_artifact_events, if_exists: true
  end
end
