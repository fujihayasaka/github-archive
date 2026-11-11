# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseMembersCanChangeRepositoryVisibilitySetting < Platform::Mutations::Base
      description "Sets whether organization members with admin permissions on a repository can change repository visibility."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set the members can change repository visibility setting.", required: true, loads: Objects::Enterprise
      argument :setting_value, Enums::EnterpriseEnabledDisabledSettingValue, "The value for the members can change repository visibility setting on the enterprise.", required: true

      field :enterprise, Objects::Enterprise, "The enterprise with the updated members can change repository visibility setting.", null: true
      field :message, String, "A message confirming the result of updating the members can change repository visibility setting.", null: true

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
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set the members can change repository visibility setting on this enterprise.")
        end

        message = ""
        case inputs[:setting_value]
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["ENABLED"]).value
          enterprise.allow_members_to_change_repo_visibility(actor: viewer, force: true)
          message = "Members can change repository visibilities and this is enforced for this enterprise."
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["DISABLED"]).value
          enterprise.block_members_from_changing_repo_visibility(actor: viewer, force: true)
          message = "Members cannot change repository visibilities and this is enforced for this enterprise."
        when T.must(Platform::Enums::EnterpriseEnabledDisabledSettingValue.values["NO_POLICY"]).value
          enterprise.clear_members_can_change_repo_visibility_setting(actor: viewer)
          message = "Policy removed for repository visibility change setting."
        end

        {
          enterprise: enterprise,
          message: message,
        }
      end
    end
  end
end
