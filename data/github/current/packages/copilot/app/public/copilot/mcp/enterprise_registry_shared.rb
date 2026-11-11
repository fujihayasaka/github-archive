# typed: strict
# frozen_string_literal: true

require "mcp_registry/enterprise_settings_client"

module Copilot
  module Mcp
    module EnterpriseRegistryShared
      include GitHub::ResilienceMixin

      sig { params(user: ::User, copilot_business: T.nilable(Copilot::Business)).returns(T::Boolean) }
      def mcp_registry_allowlist_ui_enabled?(user, copilot_business)
        business = copilot_business&.business_object
        business&.feature_flag_enabled?(:copilot_mcp_registry_enterprise_allowlist_ui, default: false) ||
          user.feature_flag_enabled?(:copilot_mcp_registry_enterprise_allowlist_ui, default: false)
      end

      sig { params(user: ::User, copilot_business: T.nilable(Copilot::Business)).returns(T::Boolean) }
      def mcp_registry_enterprise_policy_visible?(user, copilot_business)
        with_database_error_fallback(fallback: false) do
          return false unless copilot_business
          return false unless mcp_registry_allowlist_ui_enabled?(user, copilot_business)

          business = copilot_business.business_object

          return false if copilot_business.copilot_standalone?
          return false if GitHub.billing_enabled? && business.downgraded_to_free_plan?
          return false unless GitHub.copilot_enabled?

          if business.trial?
            business.dfd_trial? || !!(::Copilot::BusinessTrial.find_by(trialable_id: business.organization_ids, state: ::Copilot::BusinessTrial::ACTIVE_STATES))
          else
            copilot_business.eligible_for_first_run_flow? || copilot_business.copilot_billable?
          end
        end
      end

      sig { params(user: ::User).returns(String) }
      def mcp_registry_token(user)
        user.signed_auth_token(
          scope: ::McpRegistry::EnterpriseSettingsClient::MCP_REGISTRY_TOKEN_SCOPE,
          expires: 5.minutes.from_now,
        )
      end
    end
  end
end
