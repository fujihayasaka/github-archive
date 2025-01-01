# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseDeployKeySetting < Platform::Mutations::Base
      description "Sets whether deploy keys are allowed to be created and used for an enterprise."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set the deploy key setting.", required: true, loads: Objects::Enterprise
      argument :setting_value, Enums::EnterpriseEnabledDisabledSettingValue, "The value for the deploy key setting on the enterprise.", required: true

      field :enterprise, Objects::Enterprise, "The enterprise with the updated deploy key setting.", null: true
      field :message, String, "A message confirming the result of updating the deploy key setting.", null: true

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
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set the deploy key setting on this enterprise.")
        end


        message = ""
        case inputs[:setting_value]
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
          enterprise.enable_deploy_key_policy(actor: viewer)
          message = "Deploy keys can now be added and used in repositories."
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
          enterprise.disable_deploy_key_policy(actor: viewer)
          message = "Deploy keys can no longer be added and used in repositories."
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
          enterprise.clear_deploy_key_policy(actor: viewer)
          message = "Organization administrators can now change this setting for individual organizations. Any new organizations created will have deploy keys disabled by default."
        end

        {
          enterprise: enterprise,
          message: message,
        }
      end
    end
  end
end
