# typed: true
# frozen_string_literal: true

class FineGrainedPermission < ApplicationRecord::Iam
  include GitHub::Validations
  extend T::Sig

  TARGET_TYPES = %w(
    Business
    MemexProject
    Organization
    Package
    Repository
    Team
  )

  validates_presence_of :action
  validates_uniqueness_of :action, case_sensitive: false
  validates :action, unicode3: true

  validates_presence_of :target_type
  validates_inclusion_of :target_type,
    in: TARGET_TYPES,
    message: "is not one of #{TARGET_TYPES}",
    allow_nil: true # Skip nil checks, this case is covered by `validates_presence_of`.

  has_many :role_permissions, dependent: :destroy
  scope :custom_roles_enabled, -> { where(custom_roles_enabled: true) }

  # Look up custom roles by target type.
  scope :custom_roles_enabled_for, ->(target_type) { where(custom_roles_enabled: true, target_type: target_type) }

  # helper for pulling just enabled enterprise role fgps
  scope :enterprise_fgps_for_custom_roles, -> { custom_roles_enabled_for("Business") }

  # helper for pulling just enabled org role fgps
  scope :org_fgps_for_custom_roles, -> { custom_roles_enabled_for("Organization") }

  # helper for pulling just enabled repo role fgps
  scope :repo_fgps_for_custom_roles, -> { custom_roles_enabled_for("Repository") }
end
