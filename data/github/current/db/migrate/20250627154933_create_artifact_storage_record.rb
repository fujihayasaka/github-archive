# typed: true
# frozen_string_literal: true

class CreateArtifactStorageRecord < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    create_table :artifact_storage_records, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :artifact_metadata_id, :bigint, unsigned: true, null: false, index: true
      t.column :registry_url, :text, limit: 256,  null: false
      t.column :registry_repository_name, :string, limit: 128, null: true
      t.column :artifact_url, :text, limit: 512, null: true
      t.timestamps
      t.column :deleted_at, :datetime, precision: 6, null: true
      t.index :registry_url, length: 256
    end
  end
end
