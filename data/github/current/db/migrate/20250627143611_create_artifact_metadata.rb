# typed: true
# frozen_string_literal: true

class CreateArtifactMetadata < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    create_table :artifact_metadata, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :tenant_id, :bigint, unsigned: true, null: false, default: 0
      t.column :owner_id, :bigint, unsigned: true, null: false
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.column :attestation_id, :bigint, unsigned: true, null: true
      t.column :name, :string, limit: 256, null: false
      t.column :version, :string, limit: 128, default: nil
      t.column :digest, :string, limit: 256, null: false
      t.column :status, :string, limit: 32, default: "Active", null: false
      t.timestamps
      t.column :deleted_at, :datetime, precision: 6, null: true
      t.index :digest
      t.index :owner_id
      t.index [:repository_id, :digest], unique: true
    end
  end
end
