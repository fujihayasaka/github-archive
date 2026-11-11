# typed: true
# frozen_string_literal: true

class AddArtifactPathToArtifactStorageRecords < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    change_table :artifact_storage_records, bulk: true do |t|
      t.column :artifact_path, :string, limit: 512, null: true
    end
  end
end
