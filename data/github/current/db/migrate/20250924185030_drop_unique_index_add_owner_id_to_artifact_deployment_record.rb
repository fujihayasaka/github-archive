# typed: true
# frozen_string_literal: true

class DropUniqueIndexAddOwnerIdToArtifactDeploymentRecord < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    change_table :artifact_deployment_records, bulk: true do |t|
      # remove the unique index
      t.remove_index [:logical_environment, :physical_environment, :cluster, :deployment_name]
      # recreate the index without the unique constraint
      t.index [:logical_environment, :physical_environment, :cluster, :deployment_name], unique: false
      t.column :owner_id, :bigint, unsigned: true, null: true
      t.index :owner_id
    end
  end
end
