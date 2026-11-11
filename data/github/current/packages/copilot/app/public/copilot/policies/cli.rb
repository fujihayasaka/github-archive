# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Cli
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable
        include Copilot::Policies::Concerns::Organization::Mailable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "cli"
        end

        sig { override.returns(String) }
        def display_name
          Copilot.copilot_cli
        end

        sig { override.returns(String) }
        def documentation_url
          Copilot.copilot_cli_documentation
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["If enabled, organizations can use GitHub Copilot #{Copilot.copilot_cli_usage }"]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members of this organization will get",
            PolicyDescriptionChunk.new(text: "GitHub Copilot #{Copilot.copilot_cli_usage }.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "You can use",
            PolicyDescriptionChunk.new(text: "GitHub Copilot #{Copilot.copilot_cli_usage }.", href: documentation_url)
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          entity.feature_flag_enabled?(:copilot_agent_cli_public_preview, default: false)
        end

        sig { override.returns(T::Boolean) }
        def dpa_covered?
          true
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_enabled_email(org, user)
          CopilotForBusinessMailer.cli_enabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_disabled_email(org, user)
          CopilotForBusinessMailer.cli_disabled_for_user(org, user).deliver_later
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          if copilot_business.feature_flag_enabled?(:copilot_agent_cli_public_preview, default: false)
            config_values[:unconfigured]
          elsif copilot_business.copilot_standalone?
            config_values[:disabled]
          else
            config_values[:enabled]
          end
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          if copilot_org.feature_flag_enabled?(:copilot_agent_cli_public_preview, default: false)
            config_values[:unconfigured]
          else
            config_values[:enabled]
          end
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
            enabled: :CLI_ENABLED,
            disabled: :CLI_DISABLED,
            no_policy: :CLI_NO_POLICY,
            unconfigured: :CLI_UNCONFIGURED,
            unknown: :CLI_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::CLI::CLI_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::CLI::CLI_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::CLI::CLI_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::CLI::CLI_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::CLI::CLI_INVALID
          }
        end
      end
    end
  end
end
