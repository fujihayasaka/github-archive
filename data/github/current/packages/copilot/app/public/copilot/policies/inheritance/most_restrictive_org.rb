# typed: strict
# frozen_string_literal: true

# This module defines the "least restrictive" rule for org policy inheritance.
# Learn more about policy inheritance here: https://github.com/github/heart-services/blob/main/docs/copilot-in-dotcom/policy-inheritance.md

# A policy being "most restrictive" on the organization means that if any of a user's organizations have the policy disabled, the user policy should be disabled (assuming entity precedence is organization).

module Copilot
  module Policies
    module Inheritance
      module MostRestrictiveOrg
        extend T::Helpers

        abstract!

        include Copilot::Policies::Inheritance::Signatures

        sig { override.params(policy_data: Copilot::Users::Policies::CopilotAllPolicies).returns([T.nilable(String), T::Boolean]) }
        def user_inherited_org_policy(policy_data)
          # if there are any associated orgs that have the policy disabled, we have matched. This is going to be the policy the user inherits assuming org precedence
          return [config_values[:disabled], true] if policy_data.any? { |data| data[:type] == :organization && data[:config] && data[:config][config_name.to_sym] == config_values[:disabled] }

          # if any of the orgs have the policy enabled, we have not matched. This is going to be the policy only if the business inheritance rule is not matched, assuming org precedence
          # for example, if the policy is defined as least restrictive biz and most restrictive org, then this value is the policy only if none of the businesses have the policy enabled
          return [config_values[:enabled], false] if policy_data.any? { |data| data[:type] == :organization && data[:config] && data[:config][config_name.to_sym] == config_values[:enabled] }

          [nil, false]
        end
      end
    end
  end
end
