# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Inheritance
      module Signatures
        extend T::Helpers
        include Copilot::PolicyInterface

        abstract!

        sig { abstract.params(policy_data: Copilot::Users::Policies::CopilotAllPolicies).returns([T.nilable(String), T::Boolean]) }
        def user_inherited_business_policy(policy_data); end

        sig { abstract.params(policy_data: Copilot::Users::Policies::CopilotAllPolicies).returns([T.nilable(String), T::Boolean]) }
        def user_inherited_org_policy(policy_data); end

        sig { abstract.params(user: Copilot::User, policy_data: T.nilable(Copilot::Users::Policies::CopilotAllPolicies), skip_ea_fallback: T::Boolean).returns(T.nilable(String)) }
        def user_inherited_policy(user, policy_data, skip_ea_fallback: false); end

        private

        # shared method for getting the ea fallback value
        sig { params(user: Copilot::User).returns(T.nilable(String)) }
        def business_copilot_provider_ea_user_fallback_policy(user)
          return nil unless user.is_enterprise_assigned_user?

          # If `is_enterprise_assigned_user?` returns true we know for sure this
          # is a Copilot::Business
          provider = T.cast(user.copilot_seat_provider, Copilot::Business)

          # Ensure that the provider has no policy set
          return nil unless no_policy?(provider)

          EaUserFallback.value(provider)
        end
      end
    end
  end
end
