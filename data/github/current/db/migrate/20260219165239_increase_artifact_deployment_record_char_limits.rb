# typed: true
# frozen_string_literal: true

class IncreaseArtifactDeploymentRecordCharLimits < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    change_table :artifact_deployment_records, bulk: true do |t|
      t.change :deployment_name, :string, limit: 256
      t.change :cluster, :string, limit: 128
      t.change :physical_environment, :string, limit: 128
      t.change :logical_environment, :string, limit: 128
    end
  end
end
