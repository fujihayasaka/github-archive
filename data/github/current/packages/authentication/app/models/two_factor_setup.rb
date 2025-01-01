# typed: true
# frozen_string_literal: true

class TwoFactorSetup
  KV_KEY_PREFIX = "two_factor_authentication_setup"
  KV_LIFETIME = 2.days

  # check if the user has started the setup process
  # if they have started the setup process withing the last KV_LIFETIME, they should have a value in GitHub::Authentication::KV
  # returns boolean
  def self.pending?(user)
    kv_values(user).any?
  end

  # starts the setup process for a user by clearing any existing configuration and generating secrets
  # this should be called any time a user begins the two factor setup process
  # returns nothing
  def self.start(user, skip_recovery_secret: false)
    existing_provider = values_for(user, :provider).first
    initialize_two_factor_setup_kv_values(user, skip_recovery_secret: skip_recovery_secret, existing_provider: existing_provider)
  end

  # returns two factor setup kv values for a user based on given keys
  def self.values_for(user, *keys)
    kv_values(user).values_at(*keys)
  end

  # used to set the sms number and provider when configuring SMS two factor
  def self.set_sms_values(user, sms_number, provider_name)
    merge_kv_values(user, { sms_number: sms_number, provider: provider_name })
  end

  # used to set the recovery codes downloaded timestamp when a user officially enables 2fa
  def self.set_recovery_codes_last_downloaded_at(user)
    user.instrument_two_factor_recovery_codes_downloaded
    merge_kv_values(user, { recovery_codes_last_downloaded_at: Time.now.utc })
  end

  # used to verify the OTP provided during the setup flow (verifies an SMS _or_ authenticator app OTP)
  # returns boolean
  def self.verify_totp(type, user, otp)
    return false if otp.blank?
    secret, app_salt_version = values_for(user, :secret, :app_salt_version)
    return false unless GitHub::TwoFactorAuthentication.verify_otp_for_setup(type, otp, secret, type == :app ? app_salt_version : nil)
    merge_kv_values(user, { verified: true })
    true
  end

  # used at the end of the two factor setup wizard to officially enable 2fa on the user account
  # creates a TwoFactorCredential record and associated SmsRegistration or TotpAppRegistration record(s)
  # preserves backup_sms_number when possible
  # returns boolean
  def self.enable_two_factor(user, type)
    secret, app_salt_version, recovery_secret, recovery_salt_version, sms_number, provider, verified, recovery_codes_downloaded_at =
      values_for(user, :secret, :app_salt_version, :recovery_secret, :recovery_salt_version, :sms_number, :provider, :verified, :recovery_codes_last_downloaded_at)
    # this is also checked at the callsite in the controller, but this should stay here as a safety net
    unless verified
      GitHub.dogstats.increment("two_factor_setup.enable_two_factor.error_unverified", tags: ["type:#{type}"])
      return false
    end

    cred_saved = false
    begin
      cred_saved = User.transaction do
        clear_orphaned_records(user)
        user.set_two_factor_checkup_date

        TwoFactorCredential.create!(
          user_id: user.id,
          encrypted_recovery_secret: recovery_secret,
          recovery_used_bitfield: 0,
          recovery_codes_viewed: true,
          recovery_codes_last_downloaded_at: recovery_codes_downloaded_at,
          recovery_salt_version: recovery_salt_version
        )

        if type == "sms"
          SmsRegistration.create!(
            user_id: user.id,
            encrypted_otp_secret: secret,
            is_primary: true,
            sms_number: sms_number,
            sms_provider: provider,
            last_otp_success_at: Time.now.utc,
            last_otp_sent_at: Time.now.utc,
            total_otp_success_count: 1,
            total_otp_sent_count: 1,
            last_used_at: Time.now.utc,
          )

          # We have already validated the number by sending a confirmation code via
          # Twilio, but it is possible that they manually messed with the form since
          # then, so we should validate it again with a final message.
          message = "You have successfully configured #{GitHub.flavor} two-factor " +
            "authentication. You will receive two-factor codes at " +
            "this number."
          GitHub::SMS.send_message(sms_number, message, user, provider: provider, reason: :two_factor_setup_confirmation)
          true
        else
          TotpAppRegistration.create!(
            user_id: user.id,
            encrypted_otp_secret: secret,
            last_used_at: Time.now.utc,
            salt_version: app_salt_version,
          )
          true
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      GitHub.dogstats.increment("two_factor_setup.enable_two_factor.record_invalid", tags: ["reason:#{e.record && e.record.errors[:uniq].present? ? "uniq_validation" : "other"}}"])
      return false
    end

    user.reload
    if cred_saved
      AccountMailer.two_factor_enable(user.two_factor_credential, false).deliver_later
      clear_kv_values(user)

      GitHub.dogstats.increment "user", tags: ["action:two_factor_enable", "reconfiguring:false"]
      GitHub.dogstats.increment("two_factor_credential", tags: [
        "action:configure_#{type}",
        "recent_security_checkup:#{user.recently_took_action_on_security_checkup?}",
        "inline:false",
      ])
    end
    cred_saved
  end

  def self.configure_app(user)
    secret, app_salt_version, verified = values_for(user, :secret, :app_salt_version, :verified)
    return false unless verified

    reconfiguring = user.totp_app_registration.present?
    begin
      User.transaction do
        user.totp_app_registration.destroy! if reconfiguring
        TotpAppRegistration.create!(
          user_id: user.id,
          encrypted_otp_secret: secret,
          last_used_at: Time.now.utc,
          salt_version: app_salt_version
        )

        # reset 2FA checkup date if a user is configuring their authenticator app and is flagged for a 2FA checkup
        user.set_two_factor_checkup_date if user.is_flagged_for_two_factor_checkup?
      end
    rescue ActiveRecord::RecordInvalid => e
      GitHub.dogstats.increment("two_factor_setup.configure_app.record_invalid", tags: ["reason:#{e.record && e.record.errors[:uniq].present? ? "uniq_validation" : "other"}}"])
      return false
    end
    user.reload
    AccountMailer.two_factor_configure_factor(user, "authenticator app", reconfiguring: reconfiguring).deliver_later
    clear_kv_values(user)

    GitHub.dogstats.increment("two_factor_credential", tags: [
      "action:configure_app",
      "reconfiguring:#{reconfiguring}",
      "recent_security_checkup:#{user.recently_took_action_on_security_checkup?}",
      "related_global_notice:#{user.two_factor_related_global_notice?}",
      "global_notice:#{user.global_notice.name}",
      "inline:true",
    ])
    true
  end

  def self.configure_sms(user)
    secret, sms_number, provider, verified = values_for(user, :secret, :sms_number, :provider, :verified)
    return false unless verified

    reconfiguring = user.two_factor_primary_sms_registration.present?
    begin
      User.transaction do
        # we only want to destroy the primary SMS registration when reconfiguring
        user.two_factor_primary_sms_registration.destroy! if reconfiguring
        SmsRegistration.create!(
          user_id: user.id,
          encrypted_otp_secret: secret,
          is_primary: true,
          sms_number: sms_number,
          sms_provider: provider,
          last_otp_success_at: Time.now.utc,
          last_otp_sent_at: Time.now.utc,
          total_otp_success_count: 1,
          total_otp_sent_count: 1,
          last_used_at: Time.now.utc,
        )
        # for any grandfathered users who have a backup SMS registration, we want to update the secret to match the new primary SMS registration secret
        user.two_factor_backup_sms_registration.update!(encrypted_otp_secret: secret) if user.two_factor_backup_sms_registration?

        # reset 2FA checkup date if a user is configuring their SMS and is flagged for a 2FA checkup
        user.set_two_factor_checkup_date if user.is_flagged_for_two_factor_checkup?
      end
    rescue ActiveRecord::RecordInvalid => e
      GitHub.dogstats.increment("two_factor_setup.configure_sms.record_invalid", tags: ["reason:#{e.record && e.record.errors[:uniq].present? ? "uniq_validation" : "other"}}"])
      return false
    end
    user.reload
    AccountMailer.two_factor_configure_factor(user, "SMS", reconfiguring: reconfiguring).deliver_later
    clear_kv_values(user)

    GitHub.dogstats.increment("two_factor_credential", tags: [
      "action:configure_sms",
      "reconfiguring:#{reconfiguring}",
      "recent_security_checkup:#{user.recently_took_action_on_security_checkup?}",
      "related_global_notice:#{user.two_factor_related_global_notice?}",
      "global_notice:#{user.global_notice.name}",
      "inline:true",
    ])
    true
  end

  def self.kv_key(user)
    "#{KV_KEY_PREFIX}:#{user.id}"
  end

  # private: returns a hash of values stored in KV
  # always returns {} if there are no values in KV
  def self.kv_values(user)
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:2fa_setup"])
    kv_json = GitHub::Authentication::KV.store.get(kv_key(user)).value! { nil }
    kv_json ? JSON.parse(kv_json, symbolize_names: true) : {}
  end
  private_class_method :kv_values

  # private: updates the KV store with the given values
  # does not override any existing keys unless they match the same key name
  def self.merge_kv_values(user, new_values)
    GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:2fa_setup"])
    GitHub::Authentication::KV.store.set(kv_key(user), kv_values(user).merge(new_values).to_json, expires: KV_LIFETIME.from_now)
  end
  private_class_method :merge_kv_values

  # private: clears any KV values for two factor setup for the given user
  def self.clear_kv_values(user)
    GitHub.dogstats.increment("authn_kv", tags: ["action:delete", "callsite:2fa_setup"])
    GitHub::Authentication::KV.store.del(kv_key(user))
  end
  private_class_method :clear_kv_values

  # private: clears the two factor setup KV values for the given user
  # and initializes it with secrets
  def self.initialize_two_factor_setup_kv_values(user, skip_recovery_secret: false, existing_provider: nil)
    initial_values = {
      secret: TwoFactorCredential.generate_secret,
    }
    # app_salt_version isn't used for the SMS scenario
    initial_values[:app_salt_version] = GitHub.app_otp_salt_version
    unless skip_recovery_secret
      initial_values[:recovery_secret] = TwoFactorCredential.generate_secret
      initial_values[:recovery_salt_version] = GitHub.recovery_code_salt_version
    end
    initial_values[:provider] = existing_provider if existing_provider.present?
    GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:2fa_setup"])
    GitHub::Authentication::KV.store.set(kv_key(user), initial_values.to_json, expires: KV_LIFETIME.from_now)
  end
  private_class_method :initialize_two_factor_setup_kv_values

  # private: destroy orphaned 2fa records before enabling 2FA
  def self.clear_orphaned_records(user)
    if user.totp_app_registration.present?
      user.totp_app_registration.destroy!
      GitHub.dogstats.increment("two_factor_setup.enable_two_factor.destroy_orphaned_record", tags: ["type:app"])
    end

    if user.two_factor_primary_sms_registration?
      user.two_factor_primary_sms_registration.destroy!
      GitHub.dogstats.increment("two_factor_setup.enable_two_factor.destroy_orphaned_record", tags: ["type:sms"])
    end
  end
  private_class_method :clear_orphaned_records
end
