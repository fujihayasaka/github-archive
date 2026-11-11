# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class ClientByok
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "client_byok"
        end

        # UI
        sig { override.returns(String) }
        def display_name
          if jetbrains_policy_text_enabled?
            "Bring Your Own Language Model Key in Select IDEs"
          else
            "Bring Your Own Language Model Key in VS Code"
          end
        end

        sig { override.returns(String) }
        def documentation_url
          "https://code.visualstudio.com/docs/copilot/customization/language-models#_bring-your-own-language-model-key"
        end

        sig { returns(String) }
        def description
          if jetbrains_policy_text_enabled?
            "Enable the use of your own third-party language model API keys for VS Code and JetBrains."
          else
            "Enable the use of your own third-party language model API keys for VS Code."
          end
        end

        sig { returns(T::Boolean) }
        def jetbrains_policy_text_enabled?
          FeatureFlag.vexi.enabled?(:byok_jetbrains_policy_text, default: false)
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            description,
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            description,
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            description,
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
          ]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        # END UI

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.feature_flag_enabled?(:copilot_client_byok, default: false)

          copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: nil)
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless copilot_plan_at_least?(user, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: nil)

          # For CFB/CFE users, skip the FF gate so the cached value stays
          # correct across FF flips. twirp_value already checks available_for?
          # and returns :invalid when the FF is off, so the client never
          # receives an "enabled" it shouldn't act on.
          user_inherited_policy(user, all_policies) || "enabled"
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :client_byok_setting
        end

        sig { override.params(business: Copilot::Business).returns(String) }
        def business_default_value(business)
          config_values[:enabled]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:enabled]
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:enabled]
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
            enabled: :CLIENT_BYOK_ENABLED,
            disabled: :CLIENT_BYOK_DISABLED,
            no_policy: :CLIENT_BYOK_NO_POLICY,
            unconfigured: :CLIENT_BYOK_UNCONFIGURED,
            unknown: :CLIENT_BYOK_UNKNOWN
          }
        end

        sig do override.returns({
            enabled: Integer,
            disabled: Integer,
            no_policy: Integer,
            unconfigured: Integer,
            invalid: Integer
          })
        end
        def twirp_values
          {
            enabled: MonolithTwirp::Copilot::Users::V1::ClientBYOK::CLIENT_BYOK_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::ClientBYOK::CLIENT_BYOK_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::ClientBYOK::CLIENT_BYOK_ENABLED, # default to enabled
            unconfigured: MonolithTwirp::Copilot::Users::V1::ClientBYOK::CLIENT_BYOK_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::ClientBYOK::CLIENT_BYOK_INVALID
          }
        end
      end
    end
  end
end
