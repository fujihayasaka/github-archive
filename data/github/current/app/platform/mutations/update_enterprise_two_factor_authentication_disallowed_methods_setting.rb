# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateEnterpriseTwoFactorAuthenticationDisallowedMethodsSetting < Platform::Mutations::Base
      description "Sets the two-factor authentication methods that users of an enterprise may not use."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise on which to set the two-factor authentication disallowed methods setting.", required: true, loads: Objects::Enterprise
      argument :setting_value, Enums::EnterpriseDisallowedMethodsSettingValue, "The value for the two-factor authentication disallowed methods setting on the enterprise.", required: true

      field :enterprise, Objects::Enterprise, "The enterprise with the updated two-factor authentication disallowed methods setting.", null: true
      field :message, String, "A message confirming the result of updating the two-factor authentication disallowed methods setting.", null: true

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
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to set the two-factor authentication disallowed methods setting on this enterprise.")
        end

        if !GitHub.auth.two_factor_authentication_enabled?
          raise Errors::Unprocessable.new("Built-in two-factor authentication is not enabled on your instance.")
        elsif GitHub.auth.builtin_auth_fallback?
          raise Errors::Unprocessable.new("Two-factor authentication can't be managed when both built-in and #{GitHub.auth.name} users are allowed.")
        end

        if !enterprise.can_disallow_two_factor_methods?
          raise Errors::Unprocessable.new("Restricting two-factor authentication methods is not supported.")
        end

        if !enterprise.two_factor_requirement_enabled?
          raise Errors::Unprocessable.new("Cannot disallow two-factor authentication methods when 2FA requirement is not enabled.")
        end

        message = ""
        if T.must(Platform::Enums::EnterpriseDisallowedMethodsSettingValue.values["NO_POLICY"]).value == inputs[:setting_value]
          enterprise.clear_disallowed_two_factor_methods(actor: viewer, log_event: true)
          message = "Cleared disallowed two-factor authentication methods for this enterprise. Individual organizations may choose to restrict 2FA methods."
        elsif T.must(Platform::Enums::EnterpriseDisallowedMethodsSettingValue.values["INSECURE"]).value == inputs[:setting_value]
          if Configurable::TwoFactorDisallowedMethods::INSECURE_METHODS.any? { |method| viewer.two_factor_configured_with?(:"#{method}") }
            raise Errors::Unprocessable.new("Your account has two-factor authentication configured with a method that would be disallowed. Update your account's 2FA settings and try again.")
          end

          enterprise.disallow_insecure_two_factor_methods(actor: viewer)
          # TODO Maya: graphql subscription to send event once job is done https://github.com/github/github/blob/master/app/platform/mutations/update_issues_bulk.rb
          message = "Disallowing insecure two-factor authentication methods for users of this enterprise and its organizations."
        end

        {
          enterprise: enterprise,
          message: message,
        }
      end
    end
  end
end
