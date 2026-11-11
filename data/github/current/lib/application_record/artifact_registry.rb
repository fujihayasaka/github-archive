# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class ArtifactRegistry < Base
    self.abstract_class = true

    def self.cluster_name
      :"artifact-registry"
    end

    connects_to database: { writing: :artifact_registry_primary, reading: :artifact_registry_readonly }
  end
end
