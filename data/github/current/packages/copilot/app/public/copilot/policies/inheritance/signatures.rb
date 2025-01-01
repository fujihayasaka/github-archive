# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Inheritance
      module Signatures
        extend T::Helpers
        include Copilot::Policy

        abstract!

        sig { abstract.params(policy_data: Copilot::Users::Policies::CopilotAllPolicies).returns([T.nilable(String), T::Boolean]) }
        def user_inherited_business_policy(policy_data); end

        sig { abstract.params(policy_data: Copilot::Users::Policies::CopilotAllPolicies).returns([T.nilable(String), T::Boolean]) }
        def user_inherited_org_policy(policy_data); end

        sig { abstract.params(user: Copilot::User, policy_data: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def user_inherited_policy(user, policy_data); end
      end
    end
  end
end
