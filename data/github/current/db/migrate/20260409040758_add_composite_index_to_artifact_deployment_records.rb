# typed: true
# frozen_string_literal: true

class AddCompositeIndexToArtifactDeploymentRecords < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def up
    change_table :artifact_deployment_records, bulk: true do |t|
      t.index [:owner_id, :cluster, :logical_environment, :physical_environment, :deleted_at],
        name: "idx_deployment_records_owner_cluster_env"

      t.remove_index name: "index_artifact_deployment_records_on_owner_id"
    end
  end

  def down
    change_table :artifact_deployment_records, bulk: true do |t|
      t.index :owner_id, name: "index_artifact_deployment_records_on_owner_id"

      t.remove_index name: "idx_deployment_records_owner_cluster_env"
    end
  end
end
