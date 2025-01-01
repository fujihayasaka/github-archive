# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseMembersCanDeleteIssuesSetting < Platform::Mutations::Base
      description "Sets the members can delete issues setting for an enterprise."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set the members can delete issues setting.", required: true, loads: Objects::Enterprise
      argument :setting_value, Enums::EnterpriseEnabledDisabledSettingValue, "The value for the members can delete issues setting on the enterprise.", required: true

      field :enterprise, Objects::Enterprise, "The enterprise with the updated members can delete issues setting.", null: true
      field :message, String, "A message confirming the result of updating the members can delete issues setting.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, **inputs)
        ensure_business_not_suspended!(enterprise)
        ensure_business_payment_completed!(enterprise)

        viewer = context[:viewer]

        unless enterprise.owner?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set the members can delete issues setting on this enterprise account.")
        end

        message = ""
        case inputs[:setting_value]
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
          enterprise.allow_members_can_delete_issues(actor: viewer, force: true)
          message = "Members can now delete issues."
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
          enterprise.disallow_members_can_delete_issues(actor: viewer, force: true)
          message = "Members can no longer delete issues."
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
          enterprise.clear_members_can_delete_issues(actor: viewer)
          message = "Organization administrators can now change this setting for individual organizations."
        end

        {
          enterprise: enterprise,
          message: message,
        }
      end
    end
  end
end
