# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseMembersCanMakePurchasesSetting < Platform::Mutations::Base
      description "Sets whether or not an organization owner can make purchases."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set the members can make purchases setting.", required: true, loads: Objects::Enterprise
      argument :setting_value, Enums::EnterpriseMembersCanMakePurchasesSettingValue, "The value for the members can make purchases setting on the enterprise.", required: true

      field :enterprise, Objects::Enterprise, "The enterprise with the updated members can make purchases setting.", null: true
      field :message, String, "A message confirming the result of updating the members can make purchases setting.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(:administer_business, resource: enterprise, repo: nil, organization: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(enterprise:, **inputs)
        ensure_business_can_use_api!(enterprise)
        business_full_plan_required!(enterprise)

        viewer = context[:viewer]

        unless enterprise.owner?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set the members can make purchases setting on this enterprise account.")
        end

        message = ""
        case inputs[:setting_value]
        when T.must(Enums::EnterpriseMembersCanMakePurchasesSettingValue.values["ENABLED"]).value
          enterprise.allow_members_can_make_purchases(actor: viewer)
          message = "Organization admins can now make purchases."
        when T.must(Enums::EnterpriseMembersCanMakePurchasesSettingValue.values["DISABLED"]).value
          enterprise.disallow_members_can_make_purchases(actor: viewer, force: true)
          message = "Organization admins can no longer make purchases."
        end

        {
          enterprise: enterprise,
          message: message,
        }
      end
    end
  end
end
