# typed: true
# frozen_string_literal: true

class Registry::OwnerMigration < ApplicationRecord::Domain::Packages
  self.table_name = :registry_owner_migration

  enum :package_type, Registry::Package.package_types
  enum :state, { inProgress: 0, migrated: 1, error: 2, retriableError: 3 }
  belongs_to :owner, class_name: "User", foreign_key: :owner_id # rubocop:todo Rails/InverseOf

  validates :owner_id, presence: true, uniqueness: { scope: :package_type }

  scope :in_progress_migration, ->(package_type) {
    where(state: :inProgress, package_type: package_type)
  }

  scope :migrated_migration, ->(package_type) {
    where(state: :migrated, package_type: package_type)
  }
end
