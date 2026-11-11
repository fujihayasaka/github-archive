# typed: strict
# frozen_string_literal: true

module Codespaces
  module EntityPolicy
    extend PolicyFilter

    ALL = "all"
    SELECTED = "selected"
    NONE = "none"

    # Unlike other policies, instead of returning a union of allowed values, we return a single value.
    # This is because the allowed values are mutually exclusive.
    # There should only really be one of these contraints at a time, but it is a safeguard.
    sig { params(business: T.nilable(Business)).returns(String) }
    def self.value(business:)
      return "" unless business
      allowlists = Codespaces::PolicyConstraint.joins(:policy_group).where(name: policy_name, policy_group: { owner: business }).pluck(:allowed_values)
      allowlists.flatten!

      return ALL if allowlists.empty?
      return NONE if allowlists.include?(NONE)
      return SELECTED if allowlists.include?(SELECTED)
      allowlists.first
    end

    sig { params(org: Organization, business: Business).returns(T::Boolean) }
    def self.org_has_membership?(org:, business:)
      get_policy_group_selected_memberships(policy_group_owner: business, entity: org).exists?
    end

    sig { override.returns(String) }
    def self.policy_name
      Codespaces::PolicyConstraint::CODESPACES_ALLOWED_ENTITIES
    end
  end
end
