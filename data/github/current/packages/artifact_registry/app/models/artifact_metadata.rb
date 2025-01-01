# typed: true
# frozen_string_literal: true

class ArtifactMetadata < ApplicationRecord::Domain::ArtifactRegistry
  include ::Repositories::BelongsToRepository

  has_many :storage_records,
    class_name: "ArtifactStorageRecord",
    foreign_key: :artifact_metadata_id,
    inverse_of: :artifact_metadata,
    dependent: :destroy

  has_many :deployment_records,
    class_name: "ArtifactDeploymentRecord",
    foreign_key: :artifact_metadata_id,
    inverse_of: :artifact_metadata,
    dependent: :destroy

  belongs_to :owner, class_name: "User"
  belongs_to_repository_via_domain

  validates :tenant_id, presence: true
  validates :owner_id, presence: true
  validates :repository_id, presence: true
  validates :attestation_id, presence: true
  validates :name, presence: true

  enum :status, { active: "Active", eol: "EOL", deleted: "Deleted" }, validate: true

  validates :name, length: { maximum: 256 }
  validates :version, length: { maximum: 128 }, allow_nil: true

  validates :digest, length: { maximum: 256 }, allow_nil: true
  validates :digest, uniqueness: { scope: :repository_id, message: "must be unique within the repository" }, allow_nil: true
  validates :digest, format: { with: /\Asha256:[a-fA-F0-9]{64}\z/, message: "must be a valid SHA256 digest" }

  def standalone?
    deployment_records.active.empty? && storage_records.empty?
  end

  def soft_delete
    self.update!(deleted_at: Time.now)
    self.update!(status: "Deleted")
  end
end
