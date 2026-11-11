# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CliCloudSessionStorage
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "cli_cloud_session_storage"
        end

        sig { override.returns(String) }
        def display_name
          "Store local sessions in the Cloud"
        end

        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { returns(String) }
        def description
          "If enabled, CLI and VSCode sessions are stored in the cloud."
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, CLI and VSCode sessions are stored in the cloud.",
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, CLI and VSCode sessions are stored in the cloud.",
          ]
        end

        sig { returns(String) }
        def organization_setting_payload_description
          "If enabled, CLI and VSCode sessions are stored in the cloud."
        end

        sig { params(copilot_user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(copilot_user)
          []
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        # Returns a virtual combined value representing both cli_cloud_session_storage
        # and cli_remote_control for display in the consolidated admin UI.
        sig { params(entity: Copilot::Types::CopilotEntity).returns(String) }
        def combined_value(entity)
          storage = value(entity)
          remote_control = Copilot::Policies::CliRemoteControl.value(entity)

          case storage
          when "disabled"
            "disabled"
          when "no_policy"
            "no_policy"
          when "enabled"
            remote_control == "enabled" ? "view_and_control" : "view_from_cloud"
          else
            # unconfigured — derive from legacy remote_control only for
            # states that clearly indicate admin intent
            if remote_control == "enabled"
              "view_and_control"
            elsif remote_control == "no_policy"
              "no_policy"
            else
              # disabled or unconfigured remote_control: treat as fresh —
              # no option pre-selected so admin must make an explicit choice
              "unconfigured"
            end
          end
        end

        # Uses combined_value to check both columns when determining if the
        # org policy is locked by the business.
        sig { override.params(org: Copilot::Organization).returns(T::Boolean) }
        def org_policy_inherited?(org)
          business = org.business
          return false unless business

          copilot_business = Copilot::Business.new(business)
          biz_combined = combined_value(copilot_business)

          return false if biz_combined == "no_policy"

          # When neither column is explicitly set, defer to the base implementation
          # which respects the copilot_unconfigured_is_inherited feature flag.
          return super if biz_combined == "unconfigured"

          # Business has an explicit combined value — org inherits and cannot edit
          true
        end

        sig { override.params(copilot_org: Copilot::Organization, value: String, force: T::Boolean, send_email: T::Boolean).void }
        def update_org(copilot_org, value, force: false, send_email: true)
          result = decompose_combined_value(value)
          if result
            storage_value, remote_control_value = result
            # Ensure both policies are writable to avoid persisting a partial state
            return unless Copilot::Policies::CliRemoteControl.available_for?(copilot_org)
            super(copilot_org, storage_value, force: force, send_email: send_email)
            Copilot::Policies::CliRemoteControl.update_org(copilot_org, remote_control_value, force: force, send_email: send_email)
          elsif force
            # Allow raw values only during business→org propagation
            super
          end
        end

        sig { override.params(copilot_business: Copilot::Business, value: String).void }
        def update_business(copilot_business, value)
          result = decompose_combined_value(value)
          return unless result

          storage_value, remote_control_value = result
          # Ensure both policies are writable to avoid persisting a partial state
          return unless Copilot::Policies::CliRemoteControl.available_for?(copilot_business)
          super(copilot_business, storage_value)
          Copilot::Policies::CliRemoteControl.update_business(copilot_business, remote_control_value)
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)

          # CfI/free users should have cloud session storage enabled by default
          return "enabled" if user.has_cfi_access?

          # CB/CE users inherit from org/business
          inherited = user_inherited_policy(user, all_policies)
          return inherited if inherited.present?

          # Respect legacy cli_remote_control: if an org/business enabled remote control
          # before this policy existed, treat storage as enabled
          legacy_rc = Copilot::Policies::CliRemoteControl.user_inherited_policy(user, all_policies, skip_ea_fallback: true)
          return "enabled" if legacy_rc == "enabled"

          "disabled"
        end

        sig { override.params(business: Copilot::Business).returns(String) }
        def business_default_value(business)
          config_values[:unconfigured]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:unconfigured]
        end

        # Accepted param values for org-level updates via the admin UI.
        sig { returns(T::Array[String]) }
        def accepted_org_param_values
          %w[disabled view_and_control view_from_cloud]
        end

        private

        # Maps a combined UI value to individual [storage, remote_control] values.
        # Returns nil for raw propagation values (e.g. "enabled") that should
        # only update cli_cloud_session_storage — CliRemoteControl handles its
        # own propagation separately.
        sig { params(combined: String).returns(T.nilable([String, String])) }
        def decompose_combined_value(combined)
          case combined
          when "view_and_control"
            %w[enabled enabled]
          when "view_from_cloud"
            %w[enabled disabled]
          when "disabled"
            %w[disabled disabled]
          when "no_policy"
            %w[no_policy no_policy]
          end
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
            enabled: :CLI_CLOUD_SESSION_STORAGE_ENABLED,
            disabled: :CLI_CLOUD_SESSION_STORAGE_DISABLED,
            no_policy: :CLI_CLOUD_SESSION_STORAGE_NO_POLICY,
            unconfigured: :CLI_CLOUD_SESSION_STORAGE_UNCONFIGURED,
            unknown: :CLI_CLOUD_SESSION_STORAGE_UNKNOWN,
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
            enabled: MonolithTwirp::Copilot::Users::V1::CliCloudSessionStorage::CLI_CLOUD_SESSION_STORAGE_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::CliCloudSessionStorage::CLI_CLOUD_SESSION_STORAGE_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::CliCloudSessionStorage::CLI_CLOUD_SESSION_STORAGE_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::CliCloudSessionStorage::CLI_CLOUD_SESSION_STORAGE_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::CliCloudSessionStorage::CLI_CLOUD_SESSION_STORAGE_INVALID,
          }
        end
      end
    end
  end
end
