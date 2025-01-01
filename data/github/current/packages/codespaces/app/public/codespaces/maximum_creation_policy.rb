# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module MaximumCreationPolicy
    extend T::Sig
    extend PolicyFilter

    # Returns the applicable maximum limit for the codespace creations by looking at org max limit policies.
    def self.get_applicable_creations_limit(billable_owner)
      return nil if billable_owner.nil?

      # Find lowest applicable policy
      get_policy_owner_maximums(
        billable_owner: billable_owner
      ).min
    end

    def self.get_limit_and_policy_owner(billable_owner)
      constraint = get_policy_constraints(
        billable_owner: billable_owner
      ).min do |a, b|
        a.maximum_value <=> b.maximum_value
      end

      [constraint&.maximum_value, constraint&.policy_group&.owner]
    end

    sig { override.returns(String) }
    def self.policy_name
      Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_CREATIONS
    end
  end
end
