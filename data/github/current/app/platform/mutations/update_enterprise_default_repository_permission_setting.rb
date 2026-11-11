# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseDefaultRepositoryPermissionSetting < Platform::Mutations::Base
      description "Sets the base repository permission for organizations in an enterprise."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set the base repository permission setting.", required: true, loads: Objects::Enterprise
      argument :setting_value, Enums::EnterpriseDefaultRepositoryPermissionSettingValue, "The value for the base repository permission setting on the enterprise.", required: true

      field :enterprise, Objects::Enterprise, "The enterprise with the updated base repository permission setting.", null: true
      field :message, String, "A message confirming the result of updating the base repository permission setting.", null: true

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
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set the base repository permission setting on this enterprise.")
        end

        message = ""
        if T.must(Platform::Enums::EnterpriseDefaultRepositoryPermissionSettingValue.values["NO_POLICY"]).value == inputs[:setting_value]
          enterprise.clear_default_repository_permission(actor: viewer)
          message = "The base repository permission policy is removed."
        else
          begin
            permission = permission_from_enum_value(inputs[:setting_value])
            enterprise.update_default_repository_permission permission, force: true, actor: viewer
            message = "The base repository permission is set to \
              \"#{Configurable::DefaultRepositoryPermission.human_friendly_value(permission)}\" \
              and is enforced for this enterprise.".squish
          rescue Configurable::DefaultRepositoryPermission::AlreadyUpdating
            raise Errors::Unprocessable.new "The base repository permission is already being updated."
          end
        end

        {
          enterprise: enterprise,
          message: message,
        }
      end

      private

      # Convert an Enums::EnterpriseDefaultRepositoryPermissionSettingValue value
      # to a string that is accepted as a valid permission by
      # Business#update_default_repository_permission.
      def permission_from_enum_value(enum_value)
        enum_value.downcase.to_sym
      end
    end
  end
end
