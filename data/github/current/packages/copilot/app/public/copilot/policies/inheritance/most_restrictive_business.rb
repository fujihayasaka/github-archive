# typed: strict
# frozen_string_literal: true

# This module defines the "most restrictive" rule for business policy inheritance.
# Learn more about policy inheritance here: https://github.com/github/heart-services/blob/main/docs/copilot-in-dotcom/policy-inheritance.md

# A policy being "most restrictive" on the business means that if any of a user's businesses have the policy disabled, the user policy should be disabled (assuming entity precedence is business).

module Copilot
  module Policies
    module Inheritance
      module MostRestrictiveBusiness
        extend T::Helpers

        abstract!

        include Copilot::Policies::Inheritance::Signatures

        sig { override.params(policy_data: Copilot::Users::Policies::CopilotAllPolicies).returns([T.nilable(String), T::Boolean]) }
        def user_inherited_business_policy(policy_data)
          # if there are any associated businesses that have the policy disabled, we have matched. This is going to be the policy the user inherits assuming business precedence
          return [config_values[:disabled], true] if policy_data.any? { |data| data[:type] == :business && data[:config] && data[:config][config_name.to_sym] == config_values[:disabled] }

          # if any of the businesses have the policy enabled, we have not matched. This is going to be the policy only if the org inheritance rule is not matched, assuming business precedence
          # for example, if the policy is defined as most restrictive biz and least restrictive org, then this value is the policy only if none of the orgs have the policy enabled
          return [config_values[:enabled], false] if policy_data.any? { |data| data[:type] == :business && data[:config] && data[:config][config_name.to_sym] == config_values[:enabled] }

          # if there are no businesses with the policy, we have not matched and should fall back to the lower precedence no matter what
          # for example, if the policy is defined as most restrictive biz and least restrictive org, then no matter what we will return the inherited org policy
          [nil, false]
        end
      end
    end
  end
end
