# typed: true
# frozen_string_literal: true

class FineGrainedPermission < ApplicationRecord::Iam # rubocop:disable GitHub/DoNotReferenceFGPModel

  include GitHub::Validations

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
end
