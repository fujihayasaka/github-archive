# typed: true
# frozen_string_literal: true

class ArtifactDeploymentRecordTag < ApplicationRecord::Domain::ArtifactRegistry
  belongs_to :deployment_record,
    class_name: "ArtifactDeploymentRecord",
    inverse_of: :deployment_record_tags

  validates :tag_name, length: { maximum: 100 }
  validates :tag_value, length: { maximum: 100 }
end
