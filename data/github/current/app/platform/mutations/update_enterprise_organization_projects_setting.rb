# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseOrganizationProjectsSetting < Platform::Mutations::Base
      description "Sets whether organization projects are enabled for an enterprise."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set the organization projects setting.", required: true, loads: Objects::Enterprise
      argument :setting_value, Enums::EnterpriseEnabledDisabledSettingValue, "The value for the organization projects setting on the enterprise.", required: true

      field :enterprise, Objects::Enterprise, "The enterprise with the updated organization projects setting.", null: true
      field :message, String, "A message confirming the result of updating the organization projects setting.", null: true

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
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set the organization projects setting on this enterprise.")
        end

        message = ""
        case inputs[:setting_value]
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
          enterprise.enable_organization_projects(actor: viewer, force: true)
          message = "Projects are enabled for all organizations for this enterprise."
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
          enterprise.disable_organization_projects(actor: viewer, force: true)
          message = "Projects are disabled for all organizations for this enterprise."
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
          enterprise.clear_organization_projects_setting(actor: viewer)
          message = "Projects policy was removed. Individual organizations may enable or disable projects."
        end

        {
          enterprise: enterprise,
          message: message,
        }
      end
    end
  end
end
