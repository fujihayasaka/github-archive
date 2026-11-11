# typed: true
# frozen_string_literal: true

module Codespaces
  class PolicyGroupMembership < ApplicationRecord::Domain::Policies
    # Note that we only support Organization targets and not just any User, but for the polymorphic association to work bidirectionally (for org.policy_groups to return anything) we need to use the base class here.
    TARGET_TYPES = [
      TARGET_TYPE_BUSINESS = "Business",
      TARGET_TYPE_USER = "User",
      TARGET_TYPE_REPOSITORY = "Repository",
    ]

    # Used by destroy_in_background_with
    def self.target_types
      TARGET_TYPES.map.with_index { |type, index| [type, index] }.to_h
    end

    belongs_to :policy_group
    has_many :policy_constraints, through: :policy_group
    belongs_to :target, polymorphic: true
    destroy_in_background_with :target, polymorphic_type_value: TARGET_TYPES.index("Repository")

    validates :policy_group_id, presence: true
    validates :target_id, presence: true, uniqueness: { scope: [:policy_group_id, :target_type] }
    validates :target_type, presence: true, inclusion: { in: TARGET_TYPES }, length: { maximum: 40 }
    validate :organization_user_target

    def organization_user_target
      if target_type == TARGET_TYPE_USER && !target.is_a?(Organization)
        errors.add(:target, "cannot be an individual user")
      end
    end
  end
end
