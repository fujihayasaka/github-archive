# typed: true
# frozen_string_literal: true

class AddIndexOnDeletedAtForArtifactStorageRecords < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    add_index :artifact_storage_records, :deleted_at, name: "index_artifact_storage_records_on_deleted_at"
  end
end
