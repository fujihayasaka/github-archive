# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIpAllowListForInstalledAppsEnabledSetting < Platform::Mutations::Base
      description "Sets whether IP allow list configuration for installed GitHub Apps is enabled on an owner."

      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      argument :owner_id, ID, "The ID of the owner.", required: true, loads: Unions::IpAllowListOwner
      argument :setting_value, Enums::IpAllowListForInstalledAppsEnabledSettingValue,
        "The value for the IP allow list configuration for installed GitHub Apps setting.",
        required: true

      field :owner, Unions::IpAllowListOwner, "The IP allow list owner on which the setting was updated.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
        if owner.is_a?(::Business)
          permission.access_allowed?(:administer_business,
            resource: owner, repo: nil, organization: nil,
            allow_integrations: false, allow_user_via_granular_actor: false)
        elsif owner.is_a?(::Organization)
          permission.access_allowed?(:v4_manage_org_users,
            resource: owner, organization: owner, current_repo: nil,
            allow_integrations: false, allow_user_via_granular_actor: false)
        else
          raise Errors::Unprocessable.new("You cannot set the IP allow list configuration for installed GitHub Apps setting on this object.")
        end
      end

      def resolve(owner:, **inputs)
        viewer = context[:viewer]

        if owner.is_a?(::Business)
          unless owner.owner?(viewer)
            raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to manage the IP allow list on this enterprise account.")
          end
        elsif owner.is_a?(::Organization)
          unless owner.adminable_by?(viewer)
            raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to manage the IP allow list on this organization.")
          end
        else
          raise Errors::Unprocessable.new("You cannot set the IP allow list configuration for installed GitHub Apps setting on this object.")
        end

        if T.must(Platform::Enums::IpAllowListForInstalledAppsEnabledSettingValue.values["ENABLED"]).value == inputs[:setting_value]
          owner.enable_ip_allowlist_app_access(actor: viewer)
        else
          owner.disable_ip_allowlist_app_access(actor: viewer)
        end

        { owner: owner }
      end
    end
  end
end
