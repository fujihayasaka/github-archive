# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Cli
      class << self
        include Copilot::PolicyInterface

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
          "Copilot CLI"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://gh.io/copilot-cli"
        end

        sig { returns(String) }
        def doc_url_scheme
          "copilot/github-copilot-cli"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["If enabled, organizations can use GitHub Copilot CLI as an assistant in the terminal"]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members of this organization will get",
            PolicyDescriptionChunk.new(text: "GitHub Copilot CLI as an assistant in the terminal.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "You can use",
            PolicyDescriptionChunk.new(text: "GitHub Copilot CLI as an assistant in the terminal.", href: documentation_url)
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
          !entity.feature_flag_enabled?(:copilot_agent_cli_ga, default: false)
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

        sig { override.params(copilot_business: Copilot::Business, value: String).void }
        def post_business_update(copilot_business, value)
          if value == "disabled" || value == "no_policy"
            Copilot::Policies::CliDirectOrgBilling.update_business(copilot_business, value)
          elsif value == "enabled"
            Copilot::Policies::CliDirectOrgBilling.update_business(copilot_business, "disabled")
            return unless record_cli_enablement_match?

            record_cli_enabled_at_for_business(copilot_business.business_object)
          end
        end

        sig { override.params(copilot_org: Copilot::Organization, value: String).void }
        def post_organization_update(copilot_org, value)
          if value == "disabled"
            Copilot::Policies::CliDirectOrgBilling.update_org(copilot_org, value)
          elsif value == "enabled"
            return unless record_cli_enablement_match?

            record_cli_enabled_at_for_org(copilot_org.organization_object)
          end
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
          config_values[:unconfigured]
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          config_values[:unconfigured]
        end

        private

        CLI_ENABLED_COHORT = "cli_enabled"

        sig { returns(T::Boolean) }
        def record_cli_enablement_match?
          return false if GitHub.enterprise?
          return false if GitHub.multi_tenant_enterprise?

          true
        end

        sig { params(organization: ::Organization).void }
        def record_cli_enabled_at_for_org(organization)
          ::InProductTargeting.domain.record_enabled(
            cohort: CLI_ENABLED_COHORT,
            organization_id: organization.id,
          )
        end

        sig { params(business: ::Business).void }
        def record_cli_enabled_at_for_business(business)
          ::InProductTargeting.domain.record_enabled(
            cohort: CLI_ENABLED_COHORT,
            enterprise_id: business.id,
          )
        end

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
