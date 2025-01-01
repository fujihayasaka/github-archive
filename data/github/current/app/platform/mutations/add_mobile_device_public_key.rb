# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AddMobileDevicePublicKey < Platform::Mutations::Base
      ExpiresAtDeprecationNotice = {
        start_date: Date.new(2024, 8, 27),
        reason: "We are deprecating expirations for mobile device keys used in mobile 2FA",
        superseded_by: "Do not rely on this field, it is currently set to a date far in the future if a device key is expirationless",
        owner: "chriskirkland",
      }

      FarFutureExpiration = Time.new(2050, 1, 1, 0, 0, 0, "+00:00")

      description "Adds a public key registrations associated with the viewer's mobile device."

      required_capabilities [:mobile_only_schema_mask]
      minimum_accepted_scopes ["user"]
      extras [:execution_errors]

      argument :type, Enums::MobileDeviceKeyType, "The type of mobile device key being added", required: true
      argument :public_key, String, "The base64 encoded key used to verify the mobile device for authentication", required: true
      argument :verification_signature, String, "A base64 encoded signature created by the device's private key used to ensure the validity of the provided public key. This is not used for authentication.", required: false
      argument :verification_message, String, "The message that was signed by the device's private key used to ensure the validity of the provided auth public key. This is not used for authentication.", required: false
      argument :device_name, String, "The mobile device name, as identifiable by the viewer, such as \"Mona Lisa's iPhone\"", required: true
      argument :device_model, String, "The mobile device model, as reported by the device's operating system, such as \"iPhone14,2\"", required: true
      argument :device_os, Enums::MobileAppType, "The mobile device operating system", required: true
      argument :is_hardware_backed, Boolean, "Tracks if the key was backed by secure hardware key storage (e.g. Secure Enclave)", required: true

      field :expires_at, Scalars::DateTime, "The time that the mobile device key expires at", null: true, deprecated: ExpiresAtDeprecationNotice

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

        register_device_key_response = mobile_device_manager.register_device_key(
          inputs[:type],
          viewer.id,
          viewer.oauth_access.try(:id),
          inputs[:device_name],
          inputs[:device_model],
          inputs[:device_os],
          inputs[:is_hardware_backed],
          inputs[:public_key],
          public_key_verification_signature: inputs[:verification_signature],
          public_key_verification_message: inputs[:verification_message],
        )

        unless register_device_key_response.success?
          raise Platform::Errors::Unprocessable.new("Failed to add mobile device key.")
        end

        payload = {
          public_key_type: inputs[:type],
          public_key_is_hardware_backed: inputs[:is_hardware_backed],
        }
        GitHub.instrument("mobile_device_public_key.create", payload)

        {
          # set expires at to a date far in the future since expiration of new device keys is deprecated
          expires_at: FarFutureExpiration,
          errors: [],
        }

      rescue Faraday::Error => err
        Failbot.report(err)
        raise Errors::ServiceUnavailable.new("Mobile authentication device actions are currently unavailable. Please try again later.")
      rescue Platform::Errors::Unprocessable => err
        error_response(err.message, execution_errors)
      rescue ArgumentError => err
        Failbot.report(err)
        error_response(err.message, execution_errors)
      rescue ::Authnd::Proto::Error => err
        Failbot.report(err)
        error_response("Failed to add mobile device key.", execution_errors)
      end

      private

      def error_response(message, execution_errors)
        Platform::UserErrors.append_legacy_mutation_error_messages_to_context(Array.wrap(message), execution_errors)
        client_error = {
          message: message,
          path: %w(input),
        }

        {
          expires_at: nil,
          errors: [client_error],
        }
      end

      def mobile_device_manager
        ::GitHub::Authnd.mobile_device_manager("github/account_login")
      end
    end
  end
end
