# typed: true
# frozen_string_literal: true

module User::TwoFactorAuthenticationDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    has_one :two_factor_credential

    scope :two_factor_disabled,
      -> {
        joins("LEFT OUTER JOIN two_factor_credentials " \
              "ON two_factor_credentials.user_id = users.id").
        where("two_factor_credentials.user_id IS NULL")
      }

    scope :two_factor_enabled,
      -> {
        joins("LEFT OUTER JOIN two_factor_credentials " \
              "ON two_factor_credentials.user_id = users.id").
        where("two_factor_credentials.user_id IS NOT NULL")
      }

    scope :with_account_two_factor_requirement,
      -> {
        includes(:two_factor_requirement_metadata)
          .references(:two_factor_requirement_metadata)
          .where(two_factor_requirement_metadata: { state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES.slice(:required, :warning, :interrupt).values })
      }

    scope :without_account_two_factor_requirement,
      -> {
        non_required_states = User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES.slice(:optional, :exempt).values

        includes(:two_factor_requirement_metadata)
          .references(:two_factor_requirement_metadata)
          .where("two_factor_requirement_metadata.id IS NULL or two_factor_requirement_metadata.state IN (?)", non_required_states)
      }

    scope :without_insecure_two_factor_methods,
      -> {
        insecure_methods = Configurable::TwoFactorDisallowedMethods::INSECURE_METHODS
        if insecure_methods.include? :sms
          joins("LEFT OUTER JOIN sms_registrations " \
            "ON sms_registrations.user_id = users.id").
          where("sms_registrations.user_id IS NULL")
        end
      }

    scope :with_insecure_two_factor_methods,
      -> {
        insecure_methods = Configurable::TwoFactorDisallowedMethods::INSECURE_METHODS
        if insecure_methods.include? :sms
          joins("LEFT OUTER JOIN sms_registrations " \
            "ON sms_registrations.user_id = users.id").
          where("sms_registrations.user_id IS NOT NULL")
        end
      }
  end

  class_methods do
    def two_factor_authenticate_with_recovery(login, recovery_code)
      user = User.find_by_login(login)
      return unless user
      user.two_factor_recover(recovery_code) ? user : nil
    end

    def otp_authenticate(login, otp, type, callsite:, allow_generic: false)
      if u = User.find_by_login_or_email(login)
        u.valid_otp?(otp, type: type, callsite: callsite, allow_generic: allow_generic) ? u : nil
      end
    end
  end

  # Public: Has this user configured their 2FA credentials?
  #
  # On Enterprise, if user migrates their account to an external authentication
  # provider that doesn't support 2FA (SAML/CAS), then 2FA is no longer enabled.
  #
  # Returns a Boolean.
  def two_factor_authentication_enabled?
    return false if is_emu_and_not_first_owner?

    async_two_factor_authentication_enabled?.sync
  end

  def async_two_factor_authentication_enabled?
    self.async_two_factor_credential.then do |two_factor_credential|
      two_factor_credential.present? && GitHub.auth.two_factor_authentication_allowed?(self)
    end
  end

  def show_low_two_factor_method_banner?(inline: false)
    return false unless self.feature_enabled?(:actionable_two_factor_security_checkup)
    return false unless self.feature_enabled?(:low_two_factor_methods_banner)
    # give them some time after enrolling in 2FA before we start nudging them about this
    return false unless two_factor_authentication_enabled? && T.must(T.must(two_factor_credential).created_at) < 3.months.ago
    # If sms_low_availability_country applies to them, don't set this banner
    return false if show_sms_low_availability_country_banner?
    return false if !inline && self.dismissed_notice?(:low_two_factor_methods, kv_store: GitHub::Authentication::KV.store)

    only_sms_configured?
  end

  def set_low_two_factor_method_banner(action)
    GitHub.dogstats.increment("global_notice.set_low_2fa_methods_banner", tags: ["action:#{action}"])
    GlobalNoticeNext.new(viewer: self).set_notice(:low_two_factor_methods)
  end

  def show_sms_low_availability_country_banner?(inline: false)
    return false unless self.feature_enabled?(:actionable_two_factor_security_checkup)
    return false unless two_factor_authentication_enabled?
    # don't nudge them right away if they have just configured SMS 2FA
    return false if two_factor_primary_sms_registration && two_factor_primary_sms_registration.created_at > 30.minutes.ago
    return false if !inline && self.dismissed_notice?(:sms_low_availability_country, kv_store: GitHub::Authentication::KV.store)
    two_factor_sms_enabled? && two_factor_primary_sms_registration.is_low_availability_country? && only_sms_configured?
  end

  def only_sms_configured?
    return false if two_factor_configured_with?(:app)
    return false if has_webauthn_credential?
    return false if gh_mobile_auth_available?
    return false if two_factor_backup_sms_registration?
    true
  end

  # Users that are outside collaborators on orgs/businesses that disallow SMS should never be allowed to use SMS as a 2FA method/fallback:
  def two_factor_sms_permitted?
    return false unless outside_collaborator_two_factor_sms_permitted?

    true
  end

  def outside_collaborator_two_factor_sms_permitted?
    self.outside_collaborator_organizations.any? do |org|
      return false if org.get_two_factor_disallowed_methods.include? :sms
    end

    true
  end

  def has_registered_security_key?
    num_registered_security_keys > 0
  end

  def num_registered_security_keys
    return @num_registered_security_keys if defined?(@num_registered_security_keys)

    # If passkeys are not enabled, previous passkeys that may have been registered when the user had passkeys enabled, will be displayed to the user as security keys.
    @num_registered_security_keys = self.passkeys_enabled? ? u2f_registrations.security_keys.size : u2f_registrations.size
  end

  def has_registered_passkey?
    num_registered_passkeys > 0
  end

  def num_registered_passkeys
    return @num_registered_passkeys if defined?(@num_registered_passkeys)
    @num_registered_passkeys = self.passkeys_enabled? ? u2f_registrations.passkeys.size : 0
  end

  # Returns a variant of:
  #
  # - "passkey"
  # - "security key"
  # - "passkey or security key"
  #
  # We mention "passkey" first (if there are both options) because we want to encourage using those.
  def available_u2f_registrations_description(device_id = nil, capitalize_first_word: false, pluralize_each: false, passkeys_only: false)
    available_types = []
    available_types.push(pluralize_each ? "passkeys" : "passkey") if has_registered_passkey?
    available_types.push(pluralize_each ? "security keys" : "security key") if !passkeys_only && has_registered_security_key?
    available_types.join(" or ").tap do |joined|
      joined.capitalize! if capitalize_first_word
    end
  end

  def has_webauthn_credential?
    return @has_webauthn_credential if defined?(@has_webauthn_credential)
    @has_webauthn_credential = u2f_registrations.any?
  end

  def webauthn_display_icon
    if has_registered_passkey? && !has_registered_security_key?
      "passkey-fill"
    else
      "shield-lock"
    end
  end

  # Returns if GitHub Mobile authentication flow is available for this user.
  # This checks if it's enabled for the user, and also checks if they are in a state where they can use it during login.
  def gh_mobile_auth_available?
    gh_mobile_auth_enabled? && display_mobile_device_auth_keys.any?
  end

  # Returns if GitHub Mobile authentication is enabled for this user.
  # This checks that the environment and user are in a state where they can use GitHub Mobile authentication.
  def gh_mobile_auth_enabled?
    return false if GitHub.enterprise?
    return false if GitHub.multi_tenant_enterprise?
    return false if is_emu_and_not_first_owner?
    return false unless GitHub.auth.two_factor_authentication_allowed?(self)
    true
  end

  # Calls authnd to find a specific mobile auth registration.
  #
  # Returns boolean for success
  def has_mobile_device_auth_key?(oauth_access_id)
    return false unless gh_mobile_auth_enabled?

    mobile_device_manager = ::GitHub::Authnd.mobile_device_manager("github/account_login")
    response = mobile_device_manager.find_device_auth_key_registration(self.id, oauth_access_id)

    response.success?
  rescue ::Authnd::Proto::Error, Faraday::Error => err
    # report the error to Sentry
    Failbot.report!(err)
    false
  end

  # Calls authnd to find all mobile auth registrations for this user.
  #
  # Returns result registrations
  def all_mobile_device_auth_keys(catalog_service: "github/account_login")
    return [] unless gh_mobile_auth_enabled?
    return @all_mobile_device_auth_keys if defined?(@all_mobile_device_auth_keys)

    mdm = ::GitHub::Authnd.mobile_device_manager(catalog_service)
    begin
      response = mdm.find_device_auth_key_registrations(self.id)
    rescue ::Authnd::Proto::Error, Faraday::Error => err
      # report the error to Sentry
      Failbot.report!(err)
      return []
    end

    mobile_registrations = response.registrations

    @all_mobile_device_auth_keys =
      if response && response.result == :RESULT_SUCCESS
        mobile_registrations
      else
        []
      end
  end

  #  Returns a subset of all_mobile_device_auth_keys, and is used to display the list of mobile devices which we
  #  expect to be active currently.  Some active auth keys may be masked by keys on a different,
  #  indistiguishable device.
  def display_mobile_device_auth_keys(catalog_service: "github/account_login")
    return [] unless gh_mobile_auth_enabled?
    return @display_current_mobile_device_auth_keys if defined?(@display_current_mobile_device_auth_keys)

    # fetch registrations from authnd
    mobile_registrations = self.all_mobile_device_auth_keys

    # filter out mobile devices that are linked to a stale/deleted oauth access id
    mobile_registrations.select! do |registration|
      oauth_access = self.oauth_accesses.find_by(id: registration.oauth_access_id)
      if oauth_access.nil?
        GitHub.dogstats.increment("mobile_device_auth_keys.oauth_access", tags: ["status:deleted"])
        next
      end
      created_at = oauth_access.created_at
      accessed_at = oauth_access.accessed_at
      created_and_never_used = (created_at && created_at < 1.year.ago) && accessed_at.nil?
      accessed_over_a_year_ago = accessed_at && accessed_at < 1.year.ago
      if created_and_never_used || accessed_over_a_year_ago
        GitHub.dogstats.increment("mobile_device_auth_keys.oauth_access", tags: ["status:stale"])
        next
      end

      registration
    end

    # order by oauth_access_id, newest to oldest
    mobile_registrations = mobile_registrations.sort_by { |key| key.oauth_access_id }.reverse

    # filter out devices that have a unique name, model and os
    @display_current_mobile_device_auth_keys = mobile_registrations.uniq { |key| [key.device_name, key.device_os, key.device_model] }
  end

  # Calls authnd to delete a mobile auth registration.
  #
  # Returns result status
  def revoke_mobile_device_auth_key(actor, oauth_access_id, reason)
    return :RESULT_FAILED_UNSUPPORTED unless gh_mobile_auth_enabled?

    mobile_device_manager = ::GitHub::Authnd.mobile_device_manager("github/account_login")
    response = mobile_device_manager.revoke_device_auth_key_by_oauth_access_id(oauth_access_id.to_i)

    if response.success?
      payload = { oauth_access_id: oauth_access_id, public_key_type: "auth", user: self }
      payload.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor)) if actor.site_admin?

      GitHub.instrument("mobile_device_public_key.delete", payload)
    end

    GitHub.dogstats.increment("mobile_2fa.revoke_registration", tags: ["reason:#{reason}", "type:auth", "result:#{response.result}"])
    response.result

  rescue Faraday::Error, ::Authnd::Proto::Error => err
    Failbot.report(err)
    GitHub.dogstats.increment("mobile_2fa.revoke_registration", tags: ["reason:#{reason}", "type:auth", "result:client_raised"])
    :RESULT_FAILED_GENERIC
  end

  # Calls authnd to delete all mobile auth registrations associated with a user.
  #
  # Returns result status
  def revoke_mobile_device_auth_keys(actor, reason)
    return :RESULT_FAILED_UNSUPPORTED unless gh_mobile_auth_enabled?

    mobile_device_manager = ::GitHub::Authnd.mobile_device_manager("github/account_login")
    response = mobile_device_manager.revoke_device_keys_by_user_id(self.id)

    if response.success?
      payload = { public_key_type: "auth", user: self }
      payload.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor)) if actor.site_admin?
      payload[:oauth_access_ids] = response.oauth_access_ids.to_a if response.oauth_access_ids.any?

      GitHub.instrument("mobile_device_public_key.bulk_delete", payload)
    end

    GitHub.dogstats.increment("mobile_2fa.bulk_revoke_registrations", tags: ["reason:#{reason}", "type:auth", "result:#{response.result}"])
    response.result

  rescue Faraday::Error, ::Authnd::Proto::Error => err
    Failbot.report(err)
    GitHub.dogstats.increment("mobile_2fa.bulk_revoke_registrations", tags: ["reason:#{reason}", "type:auth", "result:client_raised"])
    :RESULT_FAILED_GENERIC
  end

  # Calls authnd to delete all mobile auth registrations associated with a user.
  #
  # Returns result status
  def revoke_mobile_device_keys_by_ids(actor, ids, reason)
    return :RESULT_FAILED_UNSUPPORTED unless gh_mobile_auth_enabled?

    mobile_device_manager = ::GitHub::Authnd.mobile_device_manager("github/account_login")
    response = mobile_device_manager.revoke_device_keys_by_ids(ids)

    if response.success?
      payload = { user: self, ids: ids }
      payload.merge!(GitHub.guarded_audit_log_staff_actor_entry(actor)) if actor.site_admin?
      payload[:oauth_access_ids] = response.oauth_access_ids.to_a if response.oauth_access_ids.any?

      GitHub.instrument("mobile_device_public_key.bulk_delete", payload)
    end

    GitHub.dogstats.increment("mobile_2fa.bulk_revoke_registrations", tags: ["reason:#{reason}", "result:#{response.result}"])
    response.result

  rescue Faraday::Error, ::Authnd::Proto::Error => err
    Failbot.report(err)
    GitHub.dogstats.increment("mobile_2fa.bulk_revoke_registrations", tags: ["reason:#{reason}", "result:client_raised"])
    :RESULT_FAILED_GENERIC
  end

  # Finds the number of oauth access rows associated to the GitHub Mobile app for this user.
  #
  # Returns the number of oauth access rows associated with the GitHub Mobile app
  def number_of_oauth_mobile_sessions
    android_app_id = Apps::Privileged.oauth_application(:android_mobile)&.id
    ios_app_id = Apps::Privileged.oauth_application(:ios_mobile)&.id

    oauth_accesses = self.oauth_accesses.where(application_id: [android_app_id, ios_app_id])

    oauth_accesses.count
  end

  # Finds the oauth access row associated to the GitHub Mobile app for this user
  #
  # Returns the oauth access row
  def oauth_access_associated_to_mobile_auth_key(oauth_access_id)
    self.oauth_accesses.find_by(id: oauth_access_id)
  end

  # Verifies the current recovery code for this account, against the
  # recovery code that the user submitted.
  #
  # If the recovery code matches, **the recovery code will be invalidated
  # and won't be usable again for this account**, and the method will
  # return `true`.
  #
  # If the recovery code doesn't match, `false` is returned.
  #
  # Whitespace in the recovery code is not taken into account
  # when performing the comparison.
  def two_factor_recover(recovery_code)
    return false unless two_factor_authentication_enabled?

    recovery_code = TwoFactorCredential.normalize_otp(recovery_code)
    cred = T.must(two_factor_credential)
    idx = cred.find_recovery_code_index(recovery_code)

    if idx.nil? || cred.recovery_code_used?(idx)
      GitHub.dogstats.increment("authentication.2fa_recovery", tags: ["result:failure"])
      return false
    end

    GitHub.dogstats.increment("authentication.2fa_recovery", tags: ["result:success"])
    cred.recovery_code_mark_used(idx)
    true
  end

  # Returns:
  #
  # authenticated_registration: - `nil` if there is no successfully authenticated registration.
  #                             - The `U2fRegistration` used to authenticate, if successful.
  def webauthn_json_authenticated_registration(reason, origin, challenge, sign_response_json_serialized)
    sign_response_hash = JSON.parse(sign_response_json_serialized)

    sign_response = WebAuthn::AuthenticatorAssertionResponse.new(
      authenticator_data: Base64.urlsafe_decode64(sign_response_hash["response"]["authenticatorData"]),
      signature: Base64.urlsafe_decode64(sign_response_hash["response"]["signature"]),
      client_data_json: Base64.urlsafe_decode64(sign_response_hash["response"]["clientDataJSON"]),
    )
    webauthn_authenticated_registration(reason, origin, challenge, sign_response_hash, sign_response)
  rescue JSON::ParserError
    nil
  end

  def passkeys_enabled?
    return false if !GitHub.passkeys_enabled? || is_emu_and_not_first_owner? || GitHub.auth.external_user?(self)
    return @passkeys_enabled if instance_variable_defined?(:@passkeys_enabled)
    @passkeys_enabled = true
  end

  # Returns security keys to be listed on the 2FA config page.
  #
  # When a user has passkeys enabled, any passkeys are
  # shown on the account security page itself and should be hidden
  # from the 2FA config page. However, we plan to support passkeys
  # as a feature preview, which means someone can enroll a passkey
  # (or upgrade a security key to one) and then *disable* the passkeys
  # feature at will. At that point, passkeys should be listed as
  # security keys on the 2FA config page again.
  #
  # Also note that this comes in handy for testing the passkey upgrade flow,
  # as it allows viewing and deleting passkeys even if the `trusted_devices`
  # flag is currently disabled.
  def security_keys_for_settings
    self.passkeys_enabled? ? u2f_registrations.security_keys : u2f_registrations
  end

  # Checks a sign-response against the challenges and the user's security keys.
  #
  # reason                 - Webauthn attempt authentication scenario (sudo, 2fa, password_reset, etc)
  # origin                 - The web origin of the client response.
  # challenge              - An challenge String.
  # response               - A WebAuthn::AuthenticatorAssertionResponse.
  # require_passkey - Only allow passkeys.
  #
  # Returns:
  #
  # authenticated_registration: - `nil` if there is no successfully authenticated registration.
  #                             - The `U2fRegistration` used to authenticate, if successful.
  def webauthn_authenticated_registration(reason, origin, challenge, sign_response_hash, sign_response, require_passkey: false)
    # There isn't a registration with the key handle from the response.
    key_handle = sign_response_hash["rawId"]
    registration = u2f_registrations.where(key_handle: key_handle).first
    error = :no_matching_credential if registration.nil?
    error = :require_user_presence if error.nil? && !sign_response.authenticator_data.user_present?
    if registration && require_passkey
      error = :require_passkey if !registration.is_passkey_registration?
      # if UV wasn't performed on this specific request even though we require it
      error = :require_user_verification if error.nil? && !sign_response.authenticator_data.user_verified?
    end

    if error
      GitHub.dogstats.increment("authentication.webauthn", tags: [
        "result:failure",
        "action:webauthn_authenticated_registration",
        "origin:#{reason}",
        "reason:#{error}",
        "presence:#{sign_response.authenticator_data.user_present?}",
        "passkey:#{registration.nil? ? "unknown" : registration.is_passkey_registration?}",
      ])

      # include credential ID (registration.key_handle) from response so that it's logged if registration lookup fails
      log_data = {  "gh.request.credential.raw_key_handle": key_handle }
      U2fRegistration.log_result("webauthn_verify_registration_attempt", self.class.name, reason, false, error, registration, log_data)
      return nil
    end

    registration.webauthn_authenticated?(reason, origin, challenge, sign_response_hash, sign_response) ? registration : nil
  end

  # valid sms or app otp
  def valid_otp?(otp, type:, callsite:, allow_generic: false)
    return false unless two_factor_authentication_enabled?
    GitHub::Logger.log_context({ "gh.enduser.id" => self.id,
      "gh.auth.otp_callsite" => callsite,
      "catalog_service" => "github/authentication" }) do
      case otp.to_s
      when TwoFactorCredential::OTP_REGEX
        return two_factor_verify_otp_for_all_2fa_registrations(otp, callsite: callsite) if type.nil? && allow_generic
        case type
        when :app
          two_factor_verify_app_otp(otp)
        when :sms
          two_factor_verify_sms_otp(otp)
        else
          false
        end
      else
        false
      end
    end
  end

  # only use this method if there's absolutely no other way to determine
  # if the OTP is for an SMS or TOTP registration.
  def valid_otp_for_all_2fa_registrations?(otp, callsite:)
    return unless two_factor_authentication_enabled?
    case otp.to_s
    when TwoFactorCredential::OTP_REGEX
      two_factor_verify_otp_for_all_2fa_registrations(otp, callsite: callsite)
    end
  end

  def allow_tfa_recovery_without_password?
    !GitHub.enterprise? && self.feature_enabled?(:tfa_recovery_without_password) && !self.suspended? && self.two_factor_authentication_enabled?
  end
end
