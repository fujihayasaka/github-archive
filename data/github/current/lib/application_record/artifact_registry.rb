# typed: true
# frozen_string_literal: true

module ApplicationRecord
  class ArtifactRegistry < Base
    self.abstract_class = true

    connects_to database: { writing: :artifact_registry_primary, reading: :artifact_registry_readonly }
  end
end
