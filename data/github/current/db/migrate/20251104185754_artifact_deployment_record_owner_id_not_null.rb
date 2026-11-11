# typed: true
# frozen_string_literal: true

class ArtifactDeploymentRecordOwnerIdNotNull < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def up
    change_column :artifact_deployment_records, :owner_id, :bigint, unsigned: true, null: false
  end

  def down
    change_column :artifact_deployment_records, :owner_id, :bigint, unsigned: true, null: true
  end
end
