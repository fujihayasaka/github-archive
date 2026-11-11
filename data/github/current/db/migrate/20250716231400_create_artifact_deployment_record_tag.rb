# typed: true
# frozen_string_literal: true

class CreateArtifactDeploymentRecordTag < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    create_table :artifact_deployment_record_tags, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :deployment_record_id, :bigint, unsigned: true, null: false, index: true
      t.column :tag_name, :string, null: false, limit: 100, index: true
      t.column :tag_value, :string, null: false, limit: 100, index: true
      t.timestamps
    end
  end
end
