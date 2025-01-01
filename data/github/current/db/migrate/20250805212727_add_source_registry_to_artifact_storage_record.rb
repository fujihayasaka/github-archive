# typed: true
# frozen_string_literal: true

class AddSourceRegistryToArtifactStorageRecord < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    change_table :artifact_storage_records, bulk: true do |t|
      t.column :source_registry, :string, limit: 128, null: true, index: true
    end
  end
end
