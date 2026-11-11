# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIpAllowListUserLevelEnforcementEnabledSetting < Platform::Mutations::Base
      docs_category :enterprise_admin
      description "Sets whether IP allow list user-level enforcement is enabled on an enterprise."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :owner_id, ID, "The ID of the owner.", required: true, loads: Unions::IpAllowListOwner
      argument :setting_value, Enums::IpAllowListUserLevelEnforcementEnabledSettingValue,
        "The value for the IP allow list user-level enforcement enabled setting.",
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
        else
          raise Errors::Unprocessable.new("You cannot set the IP allow list user-level enforcement setting on this object.")
        end
      end

      def resolve(owner:, **inputs)
        viewer = context[:viewer]

        if owner.is_a?(::Business)
          unless owner.owner?(viewer)
            raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to manage the IP allow list on this enterprise account.")
          end

          unless owner.eligible_for_ip_allowlist_user_level_enforcement?
            raise Errors::Unprocessable.new("This enterprise is not eligible for IP allow list user-level enforcement.")
          end

          unless owner.ip_allowlist_enabled?
            raise Errors::Unprocessable.new("IP allow list must be enabled before enabling IP allow list user-level enforcement.")
          end
        else
          raise Errors::Unprocessable.new("You cannot set the IP allow list user-level enforcement setting on this object.")
        end

        if T.must(Platform::Enums::IpAllowListUserLevelEnforcementEnabledSettingValue.values["ENABLED"]).value == inputs[:setting_value]
          owner.enable_ip_allowlist_user_level_enforcement(actor: viewer)
        else
          owner.disable_ip_allowlist_user_level_enforcement(actor: viewer)
        end

        { owner: owner }
      end
    end
  end
end
