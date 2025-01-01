# typed: strict
# frozen_string_literal: true

module Codespaces
  # This wraps ::Business with Codespace-specific logic.
  class BusinessDelegator
    extend T::Sig

    include GitHub::Memoizer

    sig { params(business: ::Business).void }
    def initialize(business)
      @business_object = business
    end

    sig { returns(::Business) }
    attr_reader :business_object

    sig { returns(T::Boolean) }
    def codespaces_enabled_for_all_organizations?
      policy_value == Codespaces::EntityPolicy::ALL
    end

    sig { returns(T::Boolean) }
    def codespaces_enabled_for_selected_organizations?
      policy_value == Codespaces::EntityPolicy::SELECTED
    end

    sig { returns(T::Boolean) }
    def codespaces_disabled?
      policy_value == Codespaces::EntityPolicy::NONE
    end

    sig { params(org: Organization).returns(T::Boolean) }
    def codespaces_disabled_for_org?(org)
      codespaces_disabled? ||
        (codespaces_enabled_for_selected_organizations? && !Codespaces::EntityPolicy.org_has_membership?(business: business_object, org: org))
    end

    sig { returns(T::Boolean) }
    def disable_codespaces!
      Codespaces::PolicyGroup.transaction do
        policy_group = PolicyGroup.business_access(business_object)
        set_with_constraint!(policy_group, Codespaces::EntityPolicy::NONE)

        policy_group.apply_universal_membership!

        true
      end
    end

    sig { returns(T::Boolean) }
    def enable_codespaces_for_all_organizations!
      Codespaces::PolicyGroup.transaction do
        policy_group = PolicyGroup.business_access(business_object)
        set_with_constraint!(policy_group, Codespaces::EntityPolicy::ALL)

        policy_group.apply_universal_membership!

        true
      end
    end

    sig { params(org_ids: T::Array[Integer]).returns(T::Boolean) }
    def enable_codespaces_for_selected_organizations!(org_ids)
      Codespaces::PolicyGroup.transaction do
        policy_group = PolicyGroup.business_access(business_object)
        set_with_constraint!(policy_group, Codespaces::EntityPolicy::SELECTED)

        if org_ids.any?
          policy_group.apply_entity_allowlist_membership!(org_ids, :organizations, destroy_old_memberships: false)
        else
          policy_group.apply_universal_membership!
        end

        true
      end
    end

    sig { params(org_ids: T::Array[Integer]).returns(T::Boolean) }
    def disable_codespaces_for_selected_organizations!(org_ids)
      return true unless org_ids.any?

      Codespaces::PolicyGroup.transaction do
        policy_group = PolicyGroup.business_access(business_object)
        raise "Business access policy must already exist" unless policy_group.persisted?
        set_with_constraint!(policy_group, Codespaces::EntityPolicy::SELECTED)

        policy_group.destroy_group_memberships(org_ids, "User")
        unless policy_group.reload.policy_group_memberships.exists?
          policy_group.apply_universal_membership! #This is done as a "placeholder" until the user selects specific orgs
        end

        true
      end
    end

    sig { returns(String) }
    memoize def policy_value
      Codespaces::EntityPolicy.value(business: business_object)
    end

    sig { returns(Integer) }
    def codespaces_enabled_organizations_count
      policy_group = Codespaces::PolicyGroup.business_access(business_object)
      return business_object.organizations.size if policy_group.nil? || codespaces_enabled_for_all_organizations?

      policy_group.policy_group_memberships.where(
        target_type: "User",
        target_filter: nil,
      ).size
    end

    sig { returns(T::Array[Integer]) }
    memoize def codespaces_selected_enabled_organization_ids
      Codespaces::PolicyGroup.business_access(business_object).policy_group_memberships.where(
        target_type: "User",
        target_filter: nil,
      ).pluck(:target_id)
    end

    sig { returns(ActiveRecord::Relation) }
    def codespaces_policy_enabled_organizations
      case
      when codespaces_enabled_for_all_organizations?
        business_object.organizations
      when codespaces_enabled_for_selected_organizations?
        business_object.organizations.where(id: codespaces_selected_enabled_organization_ids)
      else
        # when disabled return empty relation
        ::Organization.none
      end
    end

    private

    # We can't use PolicyGroup#apply_constraints here like other things writing policies.
    # This is to sidestep the fact that this is using a special reserved policy name (the
    # PG must be saved first, but the PC must already exist in memory).
    sig { params(policy_group: Codespaces::PolicyGroup, value: String).void }
    def set_with_constraint!(policy_group, value)
      policy_constraint = policy_group.policy_constraints.find_or_initialize_by(name: Codespaces::PolicyConstraint::CODESPACES_ALLOWED_ENTITIES)
      policy_constraint.value = [value]
      policy_group.save!
      policy_constraint.save!
    end
  end
end
