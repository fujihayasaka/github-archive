# typed: strict
# frozen_string_literal: true

# For users with enterprise-assigned Copilot seats, the traditional inheritance
# scheme doesn't work, since enterprises can set a policy to "No policy" causing
# the user policy to fallback to their orgs policy. EA users don't have an org,
# so this allows enterprises to specify what the fallback should be when
# a business has a policy set to "no policy".

module Copilot
  module Policies
    class EaUserFallback
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable

        include Copilot::Policies::Concerns::Instrumentable

        sig { override.returns(String) }
        def config_name
          "ea_user_fallback_policy"
        end

        sig { override.returns(String) }
        def display_name
          "Policies for enterprise-assigned users"
        end

        # no docs for this one
        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["Enable all Copilot features set to \"Let organizations decide\" for users with a Copilot license assigned directly from the enterprise."]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.sorbet_class == ::Business
          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        # always 'disabled' at the user level.
        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          "disabled"
        end

        sig { override.returns(T::Boolean) }
        def skip_organization_instrumentation?
          true
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
        end

        sig { override.params(business: Copilot::Business).returns(String) }
        def business_default_value(business)
          config_values[:disabled]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:disabled]
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:disabled]
        end

        private

        sig do override.returns({
            enabled: Symbol,
            disabled: Symbol,
            no_policy: Symbol,
            unconfigured: Symbol,
            unknown: Symbol
          })
        end
        def instrumentation_symbols
          {
            enabled: :EA_USER_FALLBACK_POLICY_ENABLED,
            disabled: :EA_USER_FALLBACK_POLICY_DISABLED,
            no_policy: :EA_USER_FALLBACK_POLICY_DISABLED,
            unconfigured: :EA_USER_FALLBACK_POLICY_DISABLED,
            unknown: :EA_USER_FALLBACK_POLICY_UNKNOWN
          }
        end
      end
    end
  end
end
