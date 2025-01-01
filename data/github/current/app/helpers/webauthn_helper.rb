# typed: true
# frozen_string_literal: true

module WebauthnHelper
  SECURITY_KEY_REGISTRATION_BUTTON_CLASSES = %w(add-u2f-registration-link js-add-u2f-registration-link btn)
  TRUSTED_DEVICE_REGISTRATION_BUTTON_CLASSES = %w(btn-block btn-primary)

  # Do browsers support WebAuthn on the request origin?
  #
  # Returns boolean.
  sig { params(request: T.nilable(ActionDispatch::Request)).returns(T::Boolean) }
  def request_origin_can_support_webauthn?(request)
    # Browsers require HTTPS for U2F to work.
    return false unless request&.ssl?

    true
  end

  def has_passkey_registrations?
    return unless passkey_user
    passkey_user.u2f_registrations&.passkeys.exists?
  end

  def passkey_intro
    "Your device supports passkeys, a password replacement that validates your identity using touch, facial recognition, a device password, or a PIN."
  end

  def passkey_definition
    "Passkeys are webauthn credentials that validate your identity using touch, facial recognition, a device password, or a PIN. They can be used as a password replacement or as a 2FA method."
  end

  def passkey_usage
    "Passkeys can be used for sign-in as a simple and secure alternative to your password and two-factor credentials."
  end

  def passkey_tfa_warning
    "Passkeys are convenient, but the best account security comes from also enabling 2FA."
  end

  # Use the heuristic of "most recent user" based on the device's
  # accessed_at value, in order to check the potential user's feature flag state.
  #
  # this is irrelevant for all non-dotcom environments (they don't use the device_id cookie)
  def passkey_user
    device_id = T.unsafe(self).current_device_id
    return unless device_id

    return @passkey_user if defined?(@passkey_user)
    @passkey_user = begin
      authed_device_with_passkey = most_recent_device_with_passkey
      return authed_device_with_passkey.user if authed_device_with_passkey

      authed_devices = AuthenticatedDevice.where(device_id: device_id).order(:accessed_at)
      verified_device = authed_devices.verified.last
      verified_device&.user
    end
  end

  # Used to show webauthn when visiting the login page.
  def show_passkey_login?
    return @show_passkeys if defined?(@show_passkeys)
    @show_passkeys = begin
      return false if !GitHub.passkeys_enabled?
      return false if T.unsafe(self).at_auth_limit?
      true
    end
  end

  private

  # The device ID may have any number of associated authenticated devices,
  # which in turn may or may not have a trsuted device available.
  #
  # Of all authenticated devices associated with the current device ID:
  # - filters down to those that have a passkey available, and
  # - returns the most recently accessed.
  #
  # Note: this does not currently check that the user associated with that
  # authenticated device still has any passkey registrations.
  def most_recent_device_with_passkey
    return @most_recent_device_with_passkey if defined?(@most_recent_device_with_passkey)
    @most_recent_device_with_passkey = begin
      potential_authenticated_devices = AuthenticatedDevice.where(device_id: T.unsafe(self).current_device_id, trusted_device_available: true).preload(:trusted_devices).order(:accessed_at)
      # Ideally we wouldn't have to do this step. But we've had at least one bug
      # where the `trusted_device_available` boolean on authenticated devices
      # got out of sync with its actual status, and this guards against such a
      # situation in the future, so that we don't actually show a prompt with
      # empty `allowCredentials`.
      authenticated_devices_with_trusted_devices = potential_authenticated_devices.select { |authenticated_device| !authenticated_device.trusted_devices.empty? }
      authenticated_devices_with_trusted_devices.last
    end
  end

  module ControllerMethods
    extend T::Helpers

    requires_ancestor { ApplicationController } # rubocop:disable GitHub/PreventViewHelpersInControllers

    # If the client sends us a `userHandle`, we use it. As of Nov. 2020, this is
    # the case:
    # - For resident key registrations.
    # - For server-side registrations in:
    #   - Chrome on macOS
    #   - Safari 14
    #   - Windows Hello
    #
    # However, it is not the case for:
    # - Android Chrome
    #
    # It's also not guaranteed by the spec (i.e. this is not a bug in Android
    # Chrome). So we fall back to the heuristic that we used to serve the
    # `allowCredentials` list on the passwordless auth prompt.
    #
    # We should also ensure that the userHandle value isn't an empty string - this will resolve the FIDO2 bad behavior from Safari
    def resolve_user_handle(sign_response_hash, tags)
      if sign_response_hash.dig("response", "userHandle").present?
        webauthn_user_handle = WebauthnUserHandle.find_by(webauthn_user_handle: Base64.urlsafe_decode64(sign_response_hash.dig("response", "userHandle")))
        return nil, :missing_user_handle if webauthn_user_handle.nil?

        user = User.find_by(id: webauthn_user_handle.user_id)
        return user, user.present? ? nil : :missing_user_for_handle
      end

      # Resolve user with credential ID if response didn't have userHandle missing
      if user.nil?
        user_ids = U2fRegistration.where(key_handle: sign_response_hash["rawId"]).pluck(:user_id)
        GitHub.dogstats.distribution("authentication.webauthn.user_handle_missing", user_ids.nil? ? 0 : user_ids.size, tags: tags)

        return nil, :multiple_users if user_ids.many?
        user = User.find_by(id: user_ids.first) if user_ids.one?
      end

      return nil, :missing_user if user.nil?
      [user, nil]
    end

    # Creates a join table record if one does not already exist and mark a passkey available.
    # Also creates an authenticated_device record if this is the first authentication request for the current device.
    # If the authenticated_device record hasn't been verified yet, we verify it here.
    #
    # Returns true if we successfully marked a passkey as available
    def associate_trusted_device_with_client(u2f_registration, association_reason)
      return false unless current_user.passkeys_enabled? && u2f_registration.is_passkey_registration?
      return false unless GitHub.sign_in_analysis_enabled? && current_device_id && parsed_useragent
      return false if serving_gist_standalone?

      is_new, authenticated_device = AuthenticatedDevice.find_device_or_create!(current_user, device_id: current_device_id,
        display_name: AuthenticatedDevice.generated_display_name(parsed_useragent))

      already_associated = current_user.trusted_device_client_registrations.where(trusted_device: u2f_registration, authenticated_device: authenticated_device).exists?
      unless already_associated
        authenticated_device.trusted_device_client_registrations.create!(trusted_device: u2f_registration, user: current_user)
      end

      trusted_device_available_before = !!authenticated_device.trusted_device_available
      success = authenticated_device.update(trusted_device_available: true)

      tags = [
        "success:#{success}",
        "association_reason:#{association_reason}",
        "already_associated:#{already_associated}",
        "trusted_device_available_before:#{trusted_device_available_before}",
        "verification_needed:#{authenticated_device.unverified?}",
        "is_new_device:#{is_new}",
        "action:#{is_new ? "create" : "update"}"
      ]

      # skips if device is already verified
      authenticated_device.verify!
      tags.append("info:no_update_needed") if !touch_authenticated_device(authenticated_device)

      GitHub.dogstats.increment("authentication.associate_trusted_device", tags: tags)
      success
    end
  end
end
