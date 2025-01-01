# typed: true
# frozen_string_literal: true

module Codespaces
  class PolicyGroup < ApplicationRecord::Domain::Policies
    extend T::Sig
    # Note that we only support Organization owners, but for the polymorphic association to work bidirectionally (for org.policy_groups to return anything) we need to use the base class here.
    OWNER_TYPES = [
      OWNER_TYPE_USER = "User",
      OWNER_TYPE_BUSINESS = "Business"
    ]

    RESERVED_POLICY_GROUP_NAME_BUSINESS_ACCESS = "Business Codespace Access Policy"

    belongs_to :owner, polymorphic: true
    has_many :policy_constraints, dependent: :destroy
    has_many :policy_group_memberships, dependent: :destroy

    validates :name, uniqueness: { scope: [:owner_id, :owner_type] }, length: { in: 1..64 }
    validate :business_access_has_corresponding_constraints, if:  -> { name == RESERVED_POLICY_GROUP_NAME_BUSINESS_ACCESS }
    validates_presence_of :name, :owner_id, :owner_type
    validates :owner_type, inclusion: { in: OWNER_TYPES }, length: { maximum: 40 }
    validate :organization_user_owner

    scope :visible, -> { where.not(name: RESERVED_POLICY_GROUP_NAME_BUSINESS_ACCESS) }

    sig { params(org: Organization).returns(T::Array[PolicyGroup]) }
    def self.parent_business_policies(org)
      return [] unless org.business
      # As a single query, returns policy groups owned by the parent business that apply to this organization.
      Codespaces::PolicyGroup.visible
        .where(owner: org.business)
        .includes(:policy_constraints, :policy_group_memberships)
        .where(policy_group_memberships: { target: [org, org.business] }).to_a
    end

    def self.business_access(business)
      self.where(owner_id: business.id, owner_type: OWNER_TYPE_BUSINESS, name: RESERVED_POLICY_GROUP_NAME_BUSINESS_ACCESS).first_or_initialize
    end

    def business_access_has_corresponding_constraints
      unless owner.is_a?(Business) && policy_constraints.any? { |constraint| constraint.name == Codespaces::PolicyConstraint::CODESPACES_ALLOWED_ENTITIES }
        errors.add(:name, "'#{name}' is a reserved policy name. Please use a different name.")
      end
    end

    def organization_user_owner
      if owner_type == OWNER_TYPE_USER && !owner.is_a?(Organization)
        errors.add(:owner, "cannot be an individual user")
      end
    end

    # Indicates that any associated policy constraints apply directly to the owner or all of its sub-resources.
    # For instance, if universal to an organization owner, any constraints would apply to all of that organization's
    # repositories (this is somewhat dependent on the where the constraint is relevant in practice). Accordingly we
    # check for a single associated PolicyGroupMembership pointed at this record's owner, and for a `nil` filter
    # (since a more targeted membership could be filtering down the owner's resources).
    def universal_under_owner?
      policy_group_memberships.exists?(target_id: owner_id, target_type: owner_type, target_filter: nil) && policy_group_memberships.count == 1
    end

    def serialized_policy_constraints
      policy_constraints.map do |constraint|
        {
          id: constraint.id,
          policy_group_id: constraint.policy_group_id,
          name: constraint.name,
          value_type: constraint.value_type,
          enabled_value: constraint.enabled_value,
          maximum_value: constraint.maximum_value,
          minimum_value: constraint.minimum_value,
          allowed_values: constraint.allowed_values,
          params: constraint.params,
          global_target_only: constraint.global_target_only?,
          isolate_constraint_to_a_single_policy: constraint.isolate_constraint_to_a_single_policy?
        }
      end
    end

    def apply_universal_membership!
      unless universal_under_owner?
        policy_group_memberships.destroy_all
        policy_group_memberships.create!(target_id: owner_id, target_type: owner_type)
      end
    end

    def apply_repo_allowlist_membership!(repository_ids)
      apply_entity_allowlist_membership!(repository_ids, :repositories)
    end

    # This method takes the entire list of ids - and removes any that aren't in the list
    def apply_entity_allowlist_membership!(entity_ids, entity_type, destroy_old_memberships: true)
      entity_ids ||= []
      if universal_under_owner?
        policy_group_memberships.destroy_all
      end

      target_type = entity_type == :organizations ? PolicyGroupMembership::TARGET_TYPE_USER : PolicyGroupMembership::TARGET_TYPE_REPOSITORY

      filtered_entity_ids = owner.send(entity_type).where(id: entity_ids).pluck(:id)
      previously_selected_entity_ids = policy_group_memberships.where(target_type: target_type).pluck(:target_id)
      new_entity_ids = filtered_entity_ids - previously_selected_entity_ids

      if destroy_old_memberships
        old_entity_ids = previously_selected_entity_ids - filtered_entity_ids
        destroy_group_memberships(old_entity_ids, target_type) if old_entity_ids.any?
      end

      return filtered_entity_ids unless new_entity_ids.any?

      new_memberships = new_entity_ids.map do |entity_id|
        { policy_group_id: id, target_id: entity_id, target_type: target_type, target_filter: nil }
      end
      policy_group_memberships.insert_all!(new_memberships)

      filtered_entity_ids
    end

    def destroy_group_memberships(target_ids, target_type)
      policy_group_memberships.where(
        target_id: target_ids,
        target_type: target_type,
        target_filter: nil,
      ).destroy_all
    end

    # Upserts the specified constraints and destroys any not mentioned.
    # constraint_data: Array of { name:, value: } per constraint.
    #
    # Write these iteratively for now, so we can still use model validations.
    def apply_constraints!(constraint_data)
      constraint_data ||= []
      if constraint_data.length == 0
        self.errors.add(:policy_constraints, "must have at least one constraint")
        raise ActiveRecord::RecordInvalid, self
      end

      existing_constraints = policy_constraints.index_by(&:name)

      constraints = []
      constraint_data.each do |c|
        constraint = existing_constraints.delete(c[:name]) || policy_constraints.new(name: c[:name])
        constraint.value = c[:value]
        constraint.save!
        constraints << constraint
      end

      # Drop any that weren't removed above and were therefore missing from the caller.
      existing_constraints.values.each(&:destroy!)

      constraints
    end
  end
end
