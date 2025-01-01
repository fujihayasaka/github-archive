# typed: true
# frozen_string_literal: true

class CreateArtifactDeploymentRecord < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    create_table :artifact_deployment_records, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :logical_environment, :string, null: false, limit: 64
      t.column :physical_environment, :string, null: false, default: "", limit: 64
      t.column :cluster, :string, null: false, default: "", limit: 64
      t.column :deployment_name, :string, null: false, limit: 128
      t.column :artifact_metadata_id, :bigint, unsigned: true, null: false, index: true
      t.timestamps
      t.column :deleted_at, :datetime, precision: 6, null: true
      t.index [:logical_environment, :physical_environment, :cluster, :deployment_name], unique: true
    end
  end
end
