# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Extensions
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::User::Cacheable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "copilot_extensions"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot Extensions"
        end

        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["Extensions can access organization data per granted permissions. Data use is subject to extension provider's terms and privacy policy. The Duplication Detection Filter does not apply to extension responses."]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          []
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          []
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          super && !copilot_user.has_limited_access? && (copilot_user.has_cfb_access? || copilot_user.has_cfe_access?)
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          # If the deprecated feature flag is enabled, the policy is not available
          return false if entity.feature_flag_enabled?(:copilot_extensions_policy_deprecated, default: false)

          entity.feature_flag_enabled?(:copilot_extension_access, default: false) || entity.feature_flag_enabled?(:copilot_extensibility_policy_override, default: false)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return "enabled" if user.feature_flag_enabled?(:copilot_extensibility_policy_override, default: false)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
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
            enabled: :COPILOT_EXTENSIONS_ENABLED,
            disabled: :COPILOT_EXTENSIONS_DISABLED,
            no_policy: :COPILOT_EXTENSIONS_NO_POLICY,
            unconfigured: :COPILOT_EXTENSIONS_UNCONFIGURED,
            unknown: :COPILOT_EXTENSIONS_UNKNOWN
          }
        end
      end
    end
  end
end
