# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class RejectMobileAuthDeviceRequest < Platform::Mutations::Base
      description "Rejects a mobile authentication request associated with a specific device."

      mobile_only true
      minimum_accepted_scopes ["user"]
      extras [:execution_errors]

      argument :request_id, Integer, "The ID associated with the mobile device authentication request.", required: true

      # signature and signature_version are ignored in authnd
      # leaving them as non-required args for backward compatibility for old clients that may still be sending them
      argument :signature, String, "The base64 encoded signature of the request.", required: false
      argument :signature_version, Enums::DeviceAuthSignatureVersion, "The signature version.", required: false

      error_fields

      GENERIC_ERROR_MESSAGE = "Failed to reject the request."

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

        reject_device_auth = mobile_device_manager.reject_device_auth(
          inputs[:request_id],
          viewer.id,
          viewer.oauth_access.try(:id)
        )

        send_errors_to_client = !reject_device_auth.success? && reject_device_auth.result != :RESULT_ALREADY_REJECTED
        if send_errors_to_client
          raise Platform::Errors::Unprocessable.new(GENERIC_ERROR_MESSAGE)
        end

        { errors: [] }

      rescue Faraday::Error => err
        Failbot.report(err)
        raise Errors::ServiceUnavailable.new(GENERIC_ERROR_MESSAGE)
      rescue Platform::Errors::Unprocessable => err
        error_response(err.message, execution_errors)
      rescue ArgumentError => err
        Failbot.report(err)
        error_response(err.message, execution_errors)
      rescue ::Authnd::Proto::Error => err
        Failbot.report(err)
        error_response(GENERIC_ERROR_MESSAGE, execution_errors)
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
