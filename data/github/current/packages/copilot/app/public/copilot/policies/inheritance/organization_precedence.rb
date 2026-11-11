# typed: strict
# frozen_string_literal: true

# Policies should include this module when they want the policy value set at the Organization level to take precedence over the value set at the Business level```
# See more about policy inheritance here: https://github.com/github/heart-services/blob/main/docs/copilot-in-dotcom/policy-inheritance.md

module Copilot
  module Policies
    module Inheritance
      module OrganizationPrecedence
        extend T::Helpers

        abstract!

        include Copilot::Policies::Inheritance::Signatures

        sig { override.params(user: Copilot::User, policy_data: T.nilable(Copilot::Users::Policies::CopilotAllPolicies), skip_ea_fallback: T::Boolean).returns(T.nilable(String)) }
        def user_inherited_policy(user, policy_data = nil, skip_ea_fallback: false)
          policy_data ||= user.all_policies

          # Find the policy inherited from the users orgs, as well as if the rule defined has been "matched"
          org_policy, org_match = user_inherited_org_policy(policy_data)
          # If we have matched the organization rule, return the organization policy
          return org_policy if org_match

          # Find the policy inherited from the users businesses, as well as if the rule defined has been "matched"
          biz_policy, biz_match = user_inherited_business_policy(policy_data)
          # If we have matched the business rule, return the business policy
          return biz_policy if biz_match

          # If neither rule is matched, return the organization policy if it exists, otherwise return the business policy
          inherited_value = org_policy || biz_policy

          if skip_ea_fallback || inherited_value.present?
            return inherited_value
          end

          business_copilot_provider_ea_user_fallback_policy(user)
        end
      end
    end
  end
end
