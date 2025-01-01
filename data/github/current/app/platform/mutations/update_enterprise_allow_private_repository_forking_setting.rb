# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseAllowPrivateRepositoryForkingSetting < Platform::Mutations::Base
      description "Sets whether private repository forks are enabled for an enterprise."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set the allow private repository forking setting.", required: true, loads: Objects::Enterprise
      argument :setting_value, Enums::EnterpriseEnabledDisabledSettingValue, "The value for the allow private repository forking setting on the enterprise.", required: true
      argument :policy_value, Enums::EnterpriseAllowPrivateRepositoryForkingPolicyValue, "The value for the allow private repository forking policy on the enterprise.", required: false
      field :enterprise, Objects::Enterprise, "The enterprise with the updated allow private repository forking setting.", null: true

      field :message, String, "A message confirming the result of updating the allow private repository forking setting.", null: true

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
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set the allow private repository forking setting on this enterprise.")
        end

        policy_value = inputs[:policy_value].downcase if inputs[:policy_value]
        should_force = false

        case inputs[:setting_value]
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
          enterprise.allow_private_repository_forking(force: should_force, actor: viewer, policy: policy_value)
          message = "Private and internal repository forks are enabled and enforced for this enterprise."
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
          enterprise.block_private_repository_forking(actor: viewer)
          message = "Private and internal repository forks are disabled and enforced for this enterprise."
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
          enterprise.clear_private_repository_forking_setting(actor: viewer)
          message = "Private and internal repository forks policy removed."
        end

        {
          enterprise: enterprise,
          message: message,
        }
      end
    end
  end
end
