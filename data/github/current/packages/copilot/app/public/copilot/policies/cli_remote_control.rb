# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CliRemoteControl
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
          "cli_remote_control"
        end

        sig { override.returns(String) }
        def display_name
          "Remote Control"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/copilot/concepts/agents/copilot-cli/about-remote-access"
        end

        sig { returns(String) }
        def description
          "If enabled, CLI sessions can be viewed and steered from github.com and GitHub Mobile."
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, CLI sessions in this enterprise can be viewed and steered from github.com and GitHub Mobile.",
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, CLI sessions in this organization can be viewed and steered from github.com and GitHub Mobile.",
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(copilot_user)
          [
            description,
          ]
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def viewable_by_business?(copilot_business)
          super && (Copilot::Policies::Cli.enabled?(copilot_business) || Copilot::Policies::Cli.no_policy?(copilot_business))
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          super && Copilot::Policies::Cli.enabled?(copilot_org)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.feature_flag_enabled?(:copilot_cli_remote_control, default: false)

          copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Free)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)

          # If cloud session storage is explicitly disabled at org/business level,
          # remote control cannot work regardless of legacy settings
          storage_inherited = Copilot::Policies::CliCloudSessionStorage.user_inherited_policy(user, all_policies, skip_ea_fallback: true)
          return "disabled" if storage_inherited == "disabled"

          # CI/free users should have remote control enabled by default
          return "enabled" if user.has_cfi_access?

          # CB/CE users inherit from org/business, defaulting to disabled
          user_inherited_policy(user, all_policies) || "disabled"
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :cli_remote_control_setting
        end

        sig { override.params(business: Copilot::Business).returns(String) }
        def business_default_value(business)
          config_values[:no_policy]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:unconfigured]
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
            enabled: :CLI_REMOTE_CONTROL_ENABLED,
            disabled: :CLI_REMOTE_CONTROL_DISABLED,
            no_policy: :CLI_REMOTE_CONTROL_NO_POLICY,
            unconfigured: :CLI_REMOTE_CONTROL_UNCONFIGURED,
            unknown: :CLI_REMOTE_CONTROL_UNKNOWN,
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
            enabled: MonolithTwirp::Copilot::Users::V1::CLIRemoteControl::CLI_REMOTE_CONTROL_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::CLIRemoteControl::CLI_REMOTE_CONTROL_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::CLIRemoteControl::CLI_REMOTE_CONTROL_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::CLIRemoteControl::CLI_REMOTE_CONTROL_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::CLIRemoteControl::CLI_REMOTE_CONTROL_INVALID,
          }
        end
      end
    end
  end
end
