# typed: true
# frozen_string_literal: true

class ArtifactRegistryDefaultLogicalEnv < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::ArtifactRegistry)

  def change
    change_column_default :artifact_deployment_records, :logical_environment, from: nil, to: ""
  end
end
