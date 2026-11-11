# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CodingAgent
      ENTERPRISE_MANAGEMENT_VALUE = T.let("coding_agent_enterprise_management".freeze, String)

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
          "swe_agent"
        end

        # Return ENTERPRISE_MANAGEMENT_VALUE when the separate column is enabled,
        # so the UI menu item shows the correct checked state.
        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(String) }
        def value(entity)
          if entity.is_a?(Copilot::Business) &&
              entity.coding_agent_enterprise_management_enabled?
            return ENTERPRISE_MANAGEMENT_VALUE
          end
          super
        end

        # When the value is ENTERPRISE_MANAGEMENT_VALUE, write to the dedicated
        # coding_agent_enterprise_management policy instead of storing it in swe_agent.
        sig { override.params(copilot_business: Copilot::Business, value: String).void }
        def update_business(copilot_business, value)
          if value == ENTERPRISE_MANAGEMENT_VALUE
            return unless available_for?(copilot_business)

            # standalone businesses do not have orgs, so enterprise management is not applicable
            return if copilot_business.is_standalone_business?

            # Write enterprise management state and no_policy in swe_agent
            copilot_business.coding_agent_enterprise_management_enabled!
            copilot_business.swe_agent_no_policy!

            GitHub.dogstats.increment(
              "copilot.settings.#{config_name}_#{value}",
              tags: ["type:business"],
            )
            GitHub.dogstats.increment(
              "copilot.settings.updated",
              tags: ["type:business", "policy_name:#{config_name}", "policy_value:#{value}"]
            )

            post_business_update(copilot_business, value)

            Copilot::NewBatchUpdateOrgSettingsJob.perform_later(copilot_business.id, config_name.to_sym)
            Copilot::BatchUpdateEnterpriseUserSettingsJob.perform_later(copilot_business.business_object)
          else
            # Clear enterprise management when switching to another value
            if copilot_business.coding_agent_enterprise_management_enabled?
              copilot_business.coding_agent_enterprise_management_disabled!
            end
            super
          end
        end

        sig { override.returns(String) }
        def display_name
          "Copilot cloud agent"
        end

        # multiple docs links
        sig { override.returns(String) }
        def documentation_url
          "https://gh.io/assigncopilot"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, users assigned a Copilot license from this enterprise will have access to #{display_name} in repositories where it is enabled. This feature may use models which are not enabled on your \"Models\" settings page.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, users assigned a Copilot license from this organization will have access to #{display_name} in repositories where it is enabled. This feature may use models which are not enabled on your Models settings page.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "Delegate tasks to #{display_name} in repositories where it is enabled.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          return false unless super

          if copilot_user.has_cfi_access?
            return true unless copilot_user.has_limited_access?
          end

          #check org for flag and plans
          return true if copilot_user.copilot_organizations.any? do |cp_org|
            enterprise_enabled = cp_org.copilot_plan_enterprise? || cp_org.on_free_copilot_enterprise_trial?
            business_enabled = cp_org.copilot_plan_business? || cp_org.on_free_copilot_business_trial?

            cp_org.copilot_enabled? && (enterprise_enabled || business_enabled)
          end

          #check business (if any) for flag and plans
          return true if copilot_user.copilot_businesses.any? do |business|
            enterprise_enabled = business.copilot_plan_enterprise? || business.on_free_copilot_enterprise_trial?
            business_enabled = business.copilot_plan_business? || business.business_object.trial?

            business.copilot_enabled? && (enterprise_enabled || business_enabled)
          end

          false
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def editable_by_org?(copilot_org)
          return false unless super

          return false if copilot_org.copilot_business&.coding_agent_enterprise_management_enabled?

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          experimental_copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro) do
            if entity.sorbet_class == ::User
              user = T.cast(entity, Copilot::User)
              return false if user.has_limited_access?
            end

            # non standalone businesses and orgs should have access, regardless of access/trial
            # also any user either paying/trial or a part of cfe/cfb biz/org should have access as well
            true
          end
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)

          # paying/trial cfi users will always have access
          return "enabled" if user.has_cfi_access? || user.has_trial_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        # after update coding agent policy, we should make sure we also update the sub policies
        sig { override.params(copilot_business: Copilot::Business, value: String).void }
        def post_business_update(copilot_business, value)
          if value == "disabled" || value == "no_policy"
            Copilot::Policies::CcaDirectOrgBilling.update_business(copilot_business, value)
          elsif value == "enabled"
            # when we re-enable the policy, reset sub policies to default
            # this only has an actual effect when changing from no policy to enabled, and ensures
            # that the value will properly propagate to the org settings
            Copilot::Policies::CcaDirectOrgBilling.update_business(copilot_business, "disabled")
          elsif value == ENTERPRISE_MANAGEMENT_VALUE
            # when switching to coding_agent_enterprise_management, reset sub policies
            # individual org enablement will be managed separately
            Copilot::Policies::CcaDirectOrgBilling.update_business(copilot_business, "disabled")
          end
        end

        # When business has coding_agent_enterprise_management enabled, do not propagate to orgs.
        # Org enablement is managed individually through the toggle UI.
        sig { params(business: Copilot::Business, org: Copilot::Organization, send_email: T::Boolean).void }
        def propagate_to_org(business, org, send_email:)
          return if business.coding_agent_enterprise_management_enabled?
          super
        end

        sig { override.params(copilot_org: Copilot::Organization, value: String).void }
        def post_organization_update(copilot_org, value)
          # if you disable coding agent at the org level, also disable sub policies
          if value == "disabled"
            Copilot::Policies::CcaDirectOrgBilling.update_org(copilot_org, value)
          end
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_enabled_email(org, user)
          CopilotSweAgentMailer.swe_agent_enabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_disabled_email(org, user)
          CopilotSweAgentMailer.swe_agent_disabled_for_user(org, user).deliver_later
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          !GitHub.multi_tenant_enterprise? || copilot_org.feature_flag_enabled?(:coding_agent_in_proxima, default: false)
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          if FeatureFlag.vexi.enabled?(:enable_cca_default, copilot_business.business_object, default: false)
            config_values[:enabled]
          else
            config_values[:unconfigured]
          end
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          if FeatureFlag.vexi.enabled?(:enable_cca_default, copilot_org.organization_object, default: false)
            config_values[:enabled]
          else
            config_values[:unconfigured]
          end
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:disabled]
        end

        # Batch-load the swe_agent policy value for a set of organizations in a single query.
        # Returns a hash mapping org ID to swe_agent string (e.g. "enabled", "disabled").
        sig { params(copilot_business: T.nilable(Copilot::Business), org_ids: T.nilable(T::Array[Integer])).returns(T::Hash[Integer, String]) }
        def coding_agent_state_by_org_id(copilot_business: nil, org_ids: nil)
          org_ids ||= copilot_business&.copilot_enabled_organization_ids
          return {} if org_ids.nil? || org_ids.empty?

          Copilot::Configuration
            .where(configurable_type: "Organization", configurable_id: org_ids)
            .select(:configurable_id, :swe_agent)
            .to_h { |config| [config.configurable_id, config.swe_agent] }
        end

        # Bulk update the coding agent policy for specific organizations within a business.
        # Used by enterprise admins to enable/disable CCA for selected orgs.
        # Only applies to orgs that belong to the given business.
        sig { params(business: Business, org_ids: T::Array[Integer], enable: T::Boolean).void }
        def bulk_update_org_policies(business:, org_ids:, enable:)
          new_config_value = enable ? config_values[:enabled] : config_values[:disabled]

          Copilot::NewBatchUpdateOrgSettingsJob.perform_later(
            business.id,
            config_name.to_sym,
            org_ids,
            new_config_value
          )
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
            enabled: :SWE_AGENT_ENABLED,
            disabled: :SWE_AGENT_DISABLED,
            no_policy: :SWE_AGENT_NO_POLICY,
            unconfigured: :SWE_AGENT_UNCONFIGURED,
            unknown: :SWE_AGENT_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_INVALID
          }
        end
      end
    end
  end
end
