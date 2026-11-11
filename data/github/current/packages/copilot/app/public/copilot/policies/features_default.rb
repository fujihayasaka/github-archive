# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class FeaturesDefault
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "features_default"
        end

        sig { override.returns(String) }
        def display_name
          "Default policy for new features"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://gh.io/copilot-features-default" # TODO: real URL
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "Automatically applied to newly released Copilot features.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url),
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "Automatically applied to newly released Copilot features.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url),
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "Automatically applied to newly released Copilot features.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url),
          ]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false if entity.is_a?(Copilot::User)

          entity.feature_flag_enabled?(:copilot_policy_defaults_available, default: false)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          # This policy will not be used at the user level
          "disabled"
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:enabled]
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          config_values[:enabled]
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:enabled]
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
        end

        private

        sig do
          override.returns({
            enabled: Symbol,
            disabled: Symbol,
            no_policy: Symbol,
            unconfigured: Symbol,
            unknown: Symbol,
          })
        end
        def instrumentation_symbols
          {
            enabled: :FEATURES_DEFAULT_ENABLED,
            disabled: :FEATURES_DEFAULT_DISABLED,
            no_policy: :FEATURES_DEFAULT_NO_POLICY,
            unconfigured: :FEATURES_DEFAULT_UNCONFIGURED,
            unknown: :FEATURES_DEFAULT_UNKNOWN,
          }
        end
      end
    end
  end
end
