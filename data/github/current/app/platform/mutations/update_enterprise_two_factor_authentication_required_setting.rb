# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseTwoFactorAuthenticationRequiredSetting < Platform::Mutations::Base
      description "Sets whether two factor authentication is required for all users in an enterprise."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set the two factor authentication required setting.", required: true, loads: Objects::Enterprise
      argument :setting_value, Enums::EnterpriseEnabledSettingValue, "The value for the two factor authentication required setting on the enterprise.", required: true

      field :enterprise, Objects::Enterprise, "The enterprise with the updated two factor authentication required setting.", null: true
      field :message, String, "A message confirming the result of updating the two factor authentication required setting.", null: true

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
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set the two factor authentication required setting on this enterprise account.")
        end

        if !GitHub.auth.two_factor_authentication_enabled?
          raise Errors::Unprocessable.new("Built-in two-factor authentication is not enabled on your instance.")
        elsif GitHub.auth.builtin_auth_fallback?
          raise Errors::Unprocessable.new("Two-factor authentication can't be enforced when both built-in and #{GitHub.auth.name} users are allowed.")
        end

        if enterprise.updating_two_factor_requirement?
          raise Errors::Unprocessable.new("The enterprise account two factor requirement is being updated.  Please wait until the update is completed before changing the setting.")
        end

        message = ""
        if T.must(Platform::Enums::EnterpriseEnabledSettingValue.values["NO_POLICY"]).value == inputs[:setting_value]
          enterprise.disable_two_factor_required(actor: viewer, log_event: true)
          message = "Disabled two-factor authentication requirement policy. Individual organizations may enable or disable two-factor authentication."
        else
          if !viewer.two_factor_authentication_enabled?
            raise Errors::Unprocessable.new("Two-factor authentication must be enabled on your personal account to require it for the enterprise account.")
          else
            count = enterprise.organizations_can_enable_two_factor_requirement(false).count

            if count > 0
              raise Errors::Unprocessable.new("Enforcing two-factor authentication would remove all admins from #{count} #{"organization".pluralize(count)}.")
            end
          end

          EnforceTwoFactorRequirementOnBusinessJob.perform_later(enterprise, viewer)
          message = "Enabling two-factor authentication requirement."
        end

        {
          enterprise: enterprise,
          message: message,
        }
      end
    end
  end
end
