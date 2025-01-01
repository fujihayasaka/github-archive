# typed: true
# frozen_string_literal: true

class PrivateRegistry::Configuration < ApplicationRecord::Notify
  extend T::Sig

  self.table_name = "private_registry_configurations"
  belongs_to :owner, polymorphic: true

  validates :owner_id, presence: true
  validates :owner_type, presence: true, inclusion: { in: %w(Organization) }

  validates :registry_type, presence: true
  validates :secret_name, presence: true
  validates :url, presence: true

  enum :registry_type, {
    maven_repository: 0,
  }, validate: true

  scope :for_organization, -> (org) { where(owner_type: "Organization", owner_id: org.id) if org.present? }

  # Convert to `PrivateRegistry::Secret`
  sig { returns(PrivateRegistry::Secret) }
  def to_secret
    PrivateRegistry::Secret.new(
      configuration: self,
      encrypted_value: nil,
      visibility: nil,
      selected_repository_ids: [],
    )
  end
end
