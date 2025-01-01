# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateNotificationRestrictionSetting < Platform::Mutations::Base
      description "Update the setting to restrict notifications to only verified or approved domains available to an owner."

      visibility :public, environments: [:enterprise, :dotcom]

      minimum_accepted_scopes ["admin:org", "admin:enterprise"]

      argument :owner_id, ID, "The ID of the owner on which to set the restrict notifications setting.", required: true, loads: Unions::VerifiableDomainOwner
      argument :setting_value, Enums::NotificationRestrictionSettingValue, "The value for the restrict notifications setting.", required: true

      field :owner, Unions::VerifiableDomainOwner, "The owner on which the setting was updated.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
        if owner.is_a?(::Business)
          permission.access_allowed?(:administer_business,
            resource: owner, repo: nil, organization: nil,
            allow_integrations: false, allow_user_via_granular_actor: false)
        elsif owner.is_a?(::Organization)
          permission.access_allowed?(:write_organization_settings,
            resource: owner, current_org: owner, current_repo: nil,
            allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(owner:, **inputs)
        begin
          case inputs[:setting_value]
          when T.must(Enums::NotificationRestrictionSettingValue.values["ENABLED"]).value
            success = owner.enable_notification_restrictions(actor: context[:viewer], force: owner.is_a?(::Business))
          when T.must(Enums::NotificationRestrictionSettingValue.values["DISABLED"]).value
            success = owner.disable_notification_restrictions(actor: context[:viewer])
          else
            raise Errors::ArgumentError.new "Unhandled value for settingValue argument"
          end

          if success
            { owner: owner }
          else
            verb = if T.must(Enums::NotificationRestrictionSettingValue.values["ENABLED"]).value == inputs[:setting_value]
              "enable"
            else
              "disable"
            end
            raise Errors::Unprocessable.new \
              "An error occurred while attempting to #{verb} notification restrictions for #{owner.to_param}"
          end
        rescue Configurable::RestrictNotificationDelivery::PlanUnsupportedError,
          Configurable::RestrictNotificationDelivery::AlreadySetOnEnterpriseError,
          Configurable::RestrictNotificationDelivery::NoVerifiedDomainsError => error
          raise Errors::Unprocessable.new(error.message)
        end
      end
    end
  end
end
