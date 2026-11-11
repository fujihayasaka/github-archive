# typed: true
# frozen_string_literal: true

class AddIndexOnDeletedAtForArtifactMetadata < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    add_index :artifact_metadata, :deleted_at, name: "index_artifact_metadata_on_deleted_at"
  end
end
