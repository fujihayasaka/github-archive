# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ApproveMobileAuthDeviceRequest < Platform::Mutations::Base
      description "Approves a mobile authentication request associated with a specific device."

      mobile_only true
      minimum_accepted_scopes ["user"]
      extras [:execution_errors]

      argument :request_id, Integer, "The ID associated with the mobile device authentication request.", required: true
      argument :signature, String, "The base64 encoded signature of the request.", required: true
      argument :signature_version, Enums::DeviceAuthSignatureVersion, "The signature version.", required: true

      error_fields

      GENERIC_ERROR_MESSAGE = "Failed to approve the request."
      WRONG_CHALLENGE_ERROR_MESSAGE = "The number you entered did not match."

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

        approve_device_auth = mobile_device_manager.approve_device_auth(
          inputs[:request_id],
          viewer.id,
          viewer.oauth_access.try(:id),
          inputs[:signature],
          inputs[:signature_version]
        )

        send_errors_to_client = !approve_device_auth.success? && approve_device_auth.result != :RESULT_ALREADY_APPROVED
        if send_errors_to_client
          if approve_device_auth.result == :RESULT_FAILED_NOT_VERIFIED
            return error_response(WRONG_CHALLENGE_ERROR_MESSAGE, execution_errors)
          end

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
