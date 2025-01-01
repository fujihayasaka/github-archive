# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteMobileDevicePublicKey < Platform::Mutations::Base
      description "Deletes the public key registration associated with the viewer's mobile device."

      mobile_only true
      minimum_accepted_scopes ["user"]
      extras [:execution_errors]

      argument :type, Enums::MobileDeviceKeyType, "The type of mobile device key to delete", required: true

      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      #
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def resolve(execution_errors:, **inputs)
        viewer = context[:viewer]

        unless inputs[:type] == T.must(Enums::MobileDeviceKeyType.values["AUTH"]).value
          raise Platform::Errors::NotImplemented.new("Only auth public key deletion is supported.")
        end

        revoke_device_key_response = mobile_device_manager.revoke_device_auth_key_by_oauth_access_id(
          viewer.oauth_access.try(:id),
        )

        if revoke_device_key_response.result == :RESULT_FAILED_NOT_FOUND
          raise Platform::Errors::NotFound.new("Could not find device public key registration.")
        elsif !revoke_device_key_response.success? && revoke_device_key_response.result != :RESULT_KEY_ALREADY_REVOKED
          raise Platform::Errors::Unprocessable.new("Failed to delete mobile device key registration.")
        end

        GitHub.instrument("mobile_device_public_key.delete", {
          public_key_type: inputs[:type],
        })

        {
          errors: [],
        }

      rescue Faraday::Error => err
        Failbot.report(err)
        raise Errors::ServiceUnavailable.new("Mobile authentication device actions are currently unavailable. Please try again later.")
      rescue Platform::Errors::Unprocessable, Platform::Errors::NotImplemented => err
        error_response(err.message, execution_errors)
      rescue ArgumentError, Platform::Errors::NotFound => err
        error_response(err.message, execution_errors)
      rescue ::Authnd::Proto::Error => err
        Failbot.report(err)
        error_response("Failed to delete mobile device key registration.", execution_errors)
      end

      private

      def error_response(message, execution_errors)
        Platform::UserErrors.append_legacy_mutation_error_messages_to_context(Array.wrap(message), execution_errors)
        client_error = {
          message: message,
          path: %w(input),
        }

        {
          errors: [client_error],
        }
      end

      def mobile_device_manager
        ::GitHub::Authnd.mobile_device_manager_for("github/account_login")
      end
    end
  end
end
