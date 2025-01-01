# typed: true
# frozen_string_literal: true

module User::TwoFactorRegistrationsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  include TwoFactorHelper
  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    has_one :totp_app_registration
    has_many :sms_registrations
  end

  UINT_MAX = 4294967295

  CONSECUTIVE_MISSED_OTP_THRESHOLD = 10
  MINIMUM_SEND_COUNT_BEFORE_CAPTCHA_EVAL = 10
  CONSECUTIVE_MISSED_OTP_CAPTCHA_THRESHOLD = 5
  CAPTCHA_SUCCESS_RATIO_THRESHOLD = 0.2
  SPAMMY_USER_SMS_LIMIT = 2

  # These countries have a high risk of SMS toll fraud and are expensive.
  # To combat this, we want to limit each SMS number with these country code to 5-15 OTPs a day.
  # 5 OTPs a day for countries with a high risk of SMS toll fraud.
  # 10 OTPs a day for countries where we have seen some SMS toll fraud.
  # 15 OTPs a day for countries where we have seen no SMS toll fraud.
  HIGH_RISK_SMS_COUNTRY_CODES_MAP = {
    "213": 10, # Algeria
    "216": 15, # Tunisia
    "218": 10, # Libya
    "221": 5, # Senegal
    "227": 15, # Niger
    "251": 10, # Ethiopia
    "257": 10, # Burundi
    "258": 5, # Mozambique
    "261": 10, # Madagascar
    "265": 10, # Malawi
    "269": 15, # Comoros
    "375": 10, # Balarus
    "501": 10, # Belize
    "52": 5, # Mexico
    "593": 5, # Ecuador
    "62": 5, # Indonesia
    "63": 5, # Philippines
    "7": 5, # Russia
    "880": 5, # Bangladesh
    "91": 10, # India
    "92": 10, # Pakistan
    "93": 10, # Afghanistan
    "94": 5, # Sri Lanka
    "961": 15, # Lebanon
    "963": 15, # Syria
    "964": 15, # Iraq
    "965": 5, # Kuwait
    "967": 15, # Yemen
    "970": 15, # Palestinian Territory
    "975": 15, # Bhutan
    "992": 15, # Tajikistan
    "994": 15, # Azerbaijan
    "996": 15, # Kyrgyzstan
    "998": 5, # Uzbekistan
  }

  LOW_AVAILABILITY_COUNTRY_CODES = [
    "234", # Nigeria
    "243", # Congo
    "244", # Angola
    "249", # Sudan
    "62", # Indonesia
    "66", # Thailand
    "86", # China
    "855", # Cambodia
    "880", # Bangladesh
    "974", # Qatar
  ].freeze

  SUSPICIOUS_SMS_SPAMMY_REASON_PATTERNS = [
    # "Account farmer (email_domains_to_flag) ...
    /email_domains_to_flag/i,
    /Fake account/i,
    /UserSignupModel score critical, enough to flag/i,
    /Email domain is served by a known bad MX server/i,
  ]

  def two_factor_primary_sms_registration?
    self.sms_registrations.any? { |r| r.is_primary? }
  end

  def two_factor_primary_sms_registration
    self.sms_registrations.find { |r| r.is_primary? }
  end

  def two_factor_backup_sms_registration?
    self.sms_registrations.any? { |r| !r.is_primary? }
  end

  def two_factor_backup_sms_registration
    self.sms_registrations.find { |r| !r.is_primary? }
  end

  # The only call-site of this function is wrapped in a User.transaction.
  # If there are any future call-sites, please make sure to wrap the call in a transaction.
  def promote_two_factor_sms_fallback_to_primary
    return false unless self.two_factor_backup_sms_registration?

    if self.two_factor_primary_sms_registration?
      self.two_factor_primary_sms_registration.destroy!
    end

    existing_registration = self.two_factor_backup_sms_registration
    existing_registration.is_primary = true
    success = existing_registration.save

    GitHub.dogstats.increment("two_factor_credential", tags: [
      "action:promote_sms_fallback_to_primary",
      "recent_security_checkup:#{self.recently_took_action_on_security_checkup?}",
      "success:#{success}"
    ])

    success
  end

  def edit_two_factor_sms_fallback(number, provider = nil)
    return false unless self.two_factor_backup_sms_registration?
    existing_registration = self.two_factor_backup_sms_registration
    existing_registration.sms_number = number
    existing_registration.sms_provider = provider unless provider.blank?
    success = existing_registration.save
    AccountMailer.configure_sms_fallback(self, number).deliver_later
    GitHub.dogstats.increment("two_factor_credential", tags: [
      "action:configure_sms_fallback",
      "edited_existing:true",
      "recent_security_checkup:#{self.recently_took_action_on_security_checkup?}",
      "related_global_notice:#{self.two_factor_related_global_notice?}",
      "global_notice:#{self.global_notice.name}",
      "success:#{success}"
    ])

    success
  end

  def remove_two_factor_sms_fallback
    success = T.cast(false, T::Boolean)
    number = self.two_factor_backup_sms_number
    User.transaction do
      if self.two_factor_backup_sms_registration
        raise ActiveRecord::Rollback unless self.two_factor_backup_sms_registration.destroy
      end
      success = true
    end
    if self.two_factor_sms_fallback_enabled?
      AccountMailer.remove_sms_fallback_for_user(self, number).deliver_later
      GitHub.dogstats.increment("two_factor_credential", tags: ["action:remove_sms_fallback", "result:#{success ? 'success' : 'failure'}"])
    end
    success
  end

  def two_factor_sms_fallback_enabled?
    self.two_factor_backup_sms_number&.present?
  end

  def two_factor_sms_blocked?(sms_number: nil, callsite: :unknown)
    number = sms_number || self.two_factor_sms_number
    country_code = GitHub::TwoFactorAuthentication.sms_country_code(number)
    blocked = false
    reason = :not_blocked
    current_registration = self.two_factor_primary_sms_registration
    missed_otp_count = current_registration&.consecutive_missed_otp_count || 0

    if self.feature_enabled?(:two_factor_sms_login_restriction_opt_out)
      reason = :opted_out
    elsif self.spammy && self.feature_enabled?(:prevent_spammy_user_sms)
      blocked = true
      reason = :spammy
    elsif matches_spammy_reasons_for_restriction?
      blocked = true if self.feature_enabled?(:enforce_spammy_reason_blockage)
      reason = :spammy_reason
    elsif user_is_spammy_and_high_risk_country_code?(number)
      blocked = true if self.feature_enabled?(:enforce_spammy_and_high_risk_country_code_blockage)
      reason = :spammy_and_high_risk_country_code
    elsif missed_otp_count >= CONSECUTIVE_MISSED_OTP_THRESHOLD
      # We give users who have missed 10 consecutive OTPs one chance a day to enter the correct TOTP code before we block them for the day
      blocked = true if current_registration.last_otp_sent_at && current_registration.last_otp_sent_at > 1.day.ago
      reason = :too_many_consecutive_misses
    elsif sms_number_at_daily_limit?(number)
      blocked = true
      reason = :sms_daily_rate_limit
      GitHub.logger.info(
        "SMS daily rate limit reached",
        "gh.enduser.id": self.id,
        "gh.sms.country_code": country_code,
        "gh.sms.callsite": callsite,
        "gh.sms.spammy_user": self.spammy,
      ) unless callsite == :stafftools
    elsif user_at_daily_sms_limit?(number)
      blocked = true
      reason = :user_daily_sms_rate_limit
      GitHub.logger.info(
        "SMS daily rate limit reached for user",
        "gh.enduser.id": self.id,
        "gh.sms.country_code": country_code,
        "gh.sms.callsite": callsite,
        "gh.sms.spammy_user": self.spammy,
      ) unless callsite == :stafftools
    end

    if reason != :not_blocked || self.spammy
      GitHub.dogstats.increment("sms_send_filter", tags: ["blocked:#{blocked}", "reason:#{reason}", "action:#{callsite}", "country:#{country_code}", "spammy:#{self.spammy}"]) unless callsite == :stafftools
    end

    [blocked, reason]
  end

  def two_factor_sms_requires_captcha?(session, callsite: :unknown)
    # this checks FF: GitHub.flipper[:octocaptcha_two_factor_sms_login].enabled?
    # This comment is required to be present to pass linting tests since this FF derrived in code.
    return false unless Octocaptcha.new(session, page: :two_factor_sms_login, user: self).show_captcha?

    show_captcha = false
    reason = :not_shown

    number = self.two_factor_sms_number
    country_code = GitHub::TwoFactorAuthentication.sms_country_code(number)
    # Example for USA: GitHub.flipper[:show_sms_login_captcha_by_country_code_1].enabled?
    # This comment is required to be present to pass linting tests since this FF derrived in code.
    country_feature = "show_sms_login_captcha_by_country_code_#{country_code}".to_sym
    spammy = self.spammy

    if self.feature_enabled?(:two_factor_sms_login_restriction_opt_out)
      reason = :opted_out
    elsif country_code && GitHub.flipper[country_feature].enabled?
      show_captcha = true
      reason = :country_override
    elsif captcha_by_sms_stats_is_enabled? && reg = self.two_factor_primary_sms_registration
      if reg.consecutive_missed_otp_count >= CONSECUTIVE_MISSED_OTP_CAPTCHA_THRESHOLD
        # Limits an attacker ASAP if they've missed 5 consecutive OTPs
        show_captcha = true
        reason = :too_many_consecutive_misses
      elsif reg.total_otp_sent_count >= MINIMUM_SEND_COUNT_BEFORE_CAPTCHA_EVAL && ((reg.total_otp_success_count.to_f / reg.total_otp_sent_count.to_f) < CAPTCHA_SUCCESS_RATIO_THRESHOLD)
        # Success ratio < 20% prevents an attacker from clearing the consecutive misses periodically completing a captcha and resuming a script
        show_captcha = true
        reason = :otp_success_ratio
      else
        # Aggregated success ratio by sms number prevents an attacker from leveraging multiple accounts with the same numbers
        aggregated_total_sent = 0
        aggregated_total_success = 0
        regs = SmsRegistration.where(sms_number: number)
        regs.each do |r|
          aggregated_total_sent = aggregated_total_sent + r.total_otp_sent_count
          aggregated_total_success = aggregated_total_success + r.total_otp_success_count
        end

        if aggregated_total_sent >= MINIMUM_SEND_COUNT_BEFORE_CAPTCHA_EVAL && ((aggregated_total_success.to_f / aggregated_total_sent.to_f) < CAPTCHA_SUCCESS_RATIO_THRESHOLD)
          show_captcha = true
          reason = :otp_success_ratio_aggregated
        end
      end
    end

    unless reason == :not_shown
      GitHub.dogstats.increment("two_factor_sms_login_captcha", tags: ["shown:#{show_captcha}", "spammy:#{spammy}", "reason:#{reason}", "country:#{country_code}", "callsite:#{callsite}"])
      GitHub.logger.info(
        "CAPTCHA shown for two factor SMS login",
        "gh.request_id" => GitHub.context[:request_id],
        "gh.enduser.id" => self.id,
        "gh.sms.spammy_user" => spammy,
        "gh.sms.reason" => reason,
        "gh.sms.country_code" => country_code,
        "gh.sms.callsite" => callsite,
      ) if show_captcha
    end

    show_captcha
  end

  def captcha_by_sms_stats_is_enabled?
    self.feature_enabled?(:two_factor_sms_login_captcha_by_sms_stats)
  end

  # Send an SMS containing the current OTP.
  #
  # use_alternate_provider - Try sending the SMS with the alternate provider.
  # callsite - symbol used solely for tracking the reason for SMS sending via stats.
  # completed_captcha - User was shown and completed a CAPTCHA before SMS was sent.
  #
  # Returns nothing.
  def send_two_factor_sms(use_alternate_provider = false, callsite: :unknown, completed_captcha: false)
    if GitHub.two_factor_sms_enabled?
      raise GitHub::SMS::UnauthorizedRecipientError.new unless self.two_factor_sms_permitted?

      blocked, _ = self.two_factor_sms_blocked?(callsite: callsite)
      raise GitHub::SMS::UnauthorizedRecipientError.new if blocked

      otp = two_factor_sms_totp.now
      message = "#{otp} is your #{GitHub.flavor} authentication code."
      message = add_origin_bound_sms_footer(message, otp)

      options = {
        reason: callsite == :unknown ? :two_factor_auth_unknown : callsite,
        completed_captcha: completed_captcha,
        provider: GitHub::SMS.provider_for(self.two_factor_sms_number, known_provider: self.two_factor_sms_provider, last_used_provider: self.two_factor_sms_provider, attempt_alternate: use_alternate_provider),
      }

      begin
        receipt = GitHub::SMS.send_message(self.two_factor_sms_number, message, self, options)
      rescue GitHub::SMS::Error => e
        GitHub.dogstats.increment("two_factor.send_two_factor_sms", tags: ["result:failed", "reason:#{e.class.name}", "country_code:#{self.two_factor_sms_number&.split(" ").first}"])
        raise
      end

      self.record_outstanding_sms_otp(otp, receipt, callsite)
      record_sms_otp_sent(use_alternate_provider, callsite, completed_captcha)
      sms_daily_rate_limit_increment(self.two_factor_sms_number)
      if self.feature_enabled?(:publish_sms_sent_event)
        GlobalInstrumenter.instrument("two_factor.sms_message_sent", {
          actor: self,
          hashed_sms_number: Digest::SHA256.hexdigest(self.two_factor_sms_number),
        })
      end
    end
  end

  def send_two_factor_fallback_sms(reason)
    if GitHub.two_factor_sms_enabled? && self.two_factor_sms_fallback_enabled?
      raise GitHub::SMS::UnauthorizedRecipientError.new unless self.two_factor_sms_permitted?

      self.two_factor_backup_sms_registration.instrument_send_fallback_sms(reason)
      GitHub.dogstats.increment("two_factor_credential", tags: ["reason:#{reason}", "action:send_fallback_sms"])

      otp = two_factor_backup_sms_totp.now
      message = "#{otp} is your #{GitHub.flavor} authentication code."
      message = add_origin_bound_sms_footer(message, otp)

      last_used_provider = self.two_factor_sms_backup_provider_data[:provider]
      new_provider = GitHub::SMS.provider_for(self.two_factor_backup_sms_number, known_provider: self.two_factor_sms_provider(for_backup_number: true), last_used_provider: last_used_provider, attempt_alternate: !!last_used_provider)
      set_two_factor_sms_backup_provider_data(new_provider)
      GitHub::SMS.send_message(self.two_factor_backup_sms_number, message, self, provider: new_provider, reason: :two_factor_auth_fallback)
      sms_daily_rate_limit_increment(self.two_factor_backup_sms_number)
    end
  end

  def two_factor_configured_with?(possible_delivery_method)
    case possible_delivery_method
    when :app
      self.totp_app_registration.present?
    when :sms
      self.two_factor_primary_sms_registration?
    else
      false
    end
  end

  def two_factor_sms_enabled?
    return false unless self.two_factor_credential
    self.two_factor_sms_number.present? && self.two_factor_configured_with?(:sms)
  end

  def app_and_sms_configured?
    return false unless self.two_factor_credential
    self.two_factor_configured_with?(:sms) && self.two_factor_configured_with?(:app)
  end

  def two_factor_app_totp
    return nil unless self.totp_app_registration.present?
    GitHub::TwoFactorAuthentication.totp(:app, T.must(self.totp_app_registration).encrypted_otp_secret, T.must(self.totp_app_registration).salt_version)
  end

  def two_factor_sms_totp
    return nil unless self.two_factor_primary_sms_registration?
    GitHub::TwoFactorAuthentication.totp(:sms, self.two_factor_primary_sms_registration.encrypted_otp_secret, nil)
  end

  def two_factor_backup_sms_totp
    return nil unless self.two_factor_backup_sms_registration?
    GitHub::TwoFactorAuthentication.totp(:sms, self.two_factor_backup_sms_registration.encrypted_otp_secret, nil)
  end

  def two_factor_sms_number
    self.two_factor_primary_sms_registration&.sms_number
  end

  def two_factor_sms_number_redacted
    self.two_factor_primary_sms_registration&.sms_number&.gsub(/\d(?=\d{4})/, "X")
  end

  def two_factor_backup_sms_number
    self.two_factor_backup_sms_registration&.sms_number
  end

  def two_factor_backup_sms_number_redacted
    self.two_factor_backup_sms_registration&.sms_number&.gsub(/\d(?=\d{4})/, "X")
  end

  # Returns the SMS provider that should be used to contact user. Prioritizes the provider for the primary
  # SMS registration by default.
  #
  # for_backup_number - If true, returns the provider for the user's backup phone number
  def two_factor_sms_provider(for_backup_number: false)
    if for_backup_number || self.two_factor_primary_sms_registration.nil?
      return self.two_factor_backup_sms_registration&.sms_provider
    end

    self.two_factor_primary_sms_registration&.sms_provider
  end

  def two_factor_recently_valid_otp?(otp, time = Time.now)
    return true if self.two_factor_configured_with?(:app) && GitHub::TwoFactorAuthentication.recently_valid_otp?(:app, otp, T.must(self.totp_app_registration).encrypted_otp_secret, T.must(self.totp_app_registration).salt_version)
    return true if self.two_factor_configured_with?(:sms) && GitHub::TwoFactorAuthentication.recently_valid_otp?(:sms, otp, self.two_factor_primary_sms_registration.encrypted_otp_secret, nil)
    false
  end

  # Finds the exact time an OTP was or will be valid, within 24 hours of now for stafftools OTP verification
  def two_factor_otp_valid_timestamp_for_stafftools(otp)
    # check app secret first if available
    if self.two_factor_configured_with?(:app)
      valid_time = GitHub::TwoFactorAuthentication.otp_valid_timestamp(:app, otp, T.must(self.totp_app_registration).encrypted_otp_secret, T.must(self.totp_app_registration).salt_version)
      return [valid_time, :app] if valid_time.present?
    end

    # check the sms secret if available
    if self.two_factor_configured_with?(:sms)
      valid_time = GitHub::TwoFactorAuthentication.otp_valid_timestamp(:sms, otp, self.two_factor_primary_sms_registration.encrypted_otp_secret, nil)
      return [valid_time, :sms] if valid_time.present?
    end

    [nil, nil]
  end

  def two_factor_verify_sms_otp(otp)
    return false unless GitHub.two_factor_sms_enabled?
    return false unless self.two_factor_credential
    return false unless self.two_factor_configured_with?(:sms)

    secret = self.two_factor_primary_sms_registration.encrypted_otp_secret
    cache_key_id = self.two_factor_primary_sms_registration.id
    verified = GitHub::TwoFactorAuthentication.verify_otp(:sms, otp, secret, nil, cache_key_id)
    if verified
      resolve_outstanding_sms_otp(otp)
      update_otp_credential_last_used_at(:sms)
      record_sms_otp_success
    end
    verified
  end

  def two_factor_verify_app_otp(otp)
    return false unless self.two_factor_credential
    return false unless self.two_factor_configured_with?(:app)

    secret = T.must(self.totp_app_registration).encrypted_otp_secret
    app_salt_version = T.must(self.totp_app_registration).salt_version
    cache_key_id = T.must(self.totp_app_registration).id
    verified = GitHub::TwoFactorAuthentication.verify_otp(:app, otp, secret, app_salt_version, cache_key_id)
    update_otp_credential_last_used_at(:app) if verified
    verified
  end

  # WARNING: only use this method if there's absolutely no other way to determine
  # if the OTP is for an SMS or TOTP registration. Ideally, we'd like to remove support for this at all callsites in the future
  # reach out to #authentication if you have any questions or need to add a new callsite
  def two_factor_verify_otp_for_all_2fa_registrations(otp, callsite:)
    return false unless self.two_factor_credential

    verified = false
    verified_using = nil
    checked_app = false
    checked_sms = false
    # check the app secret first if available
    if self.two_factor_configured_with?(:app)
      checked_app = true
      secret = T.must(self.totp_app_registration).encrypted_otp_secret
      app_salt_version = T.must(self.totp_app_registration).salt_version
      cache_key_id = T.must(self.totp_app_registration).id
      verified = GitHub::TwoFactorAuthentication.verify_otp(:app, otp, secret, app_salt_version, cache_key_id)
      verified_using = :app if verified
    end
    # if the app secret didn't check out above and we have an sms secret, check that
    if !verified && self.two_factor_configured_with?(:sms)
      checked_sms = true
      secret = self.two_factor_primary_sms_registration.encrypted_otp_secret
      cache_key_id = self.two_factor_primary_sms_registration.id
      verified = GitHub::TwoFactorAuthentication.verify_otp(:sms, otp, secret, nil, cache_key_id)
      if verified
        resolve_outstanding_sms_otp(otp)
        verified_using = :sms
        record_sms_otp_success
      end
    end

    update_otp_credential_last_used_at(verified_using) if verified
    GitHub.dogstats.increment("two_factor_auth.two_factor_verify_otp_for_all_2fa_registrations", tags: ["result:#{verified ? 'success' : 'failure'}", "checked_app:#{checked_app}", "checked_sms:#{checked_sms}", "verified_using:#{verified_using}", "callsite:#{callsite}"])
    !!verified
  end

  # In the most common case, this logic represents someone attempting to reuse
  # a valid OTP but in reality, this represents someone trying to use a code
  # older than the last currently validated otp. Since the window of validity
  # allows from some slack on both ends, it's possible to validate an "older"
  # token while "younger" tokens are still valid.
  def reused_valid_totp?(otp, type:, allow_generic: false)
    if type.nil? && allow_generic
      reused = false
      if self.two_factor_configured_with?(:app)
        reused = !self.two_factor_verify_app_otp(otp) && self.two_factor_app_totp.verify(otp, drift_ahead: TwoFactorCredential::ALLOWABLE_DRIFT, drift_behind: TwoFactorCredential::ALLOWABLE_DRIFT)
        return true if reused
      end
      if self.two_factor_configured_with?(:sms)
        return !self.two_factor_verify_sms_otp(otp) && self.two_factor_sms_totp.verify(otp, drift_ahead: TwoFactorCredential::ALLOWABLE_DRIFT, drift_behind: TwoFactorCredential::ALLOWABLE_DRIFT)
      end
      return false
    end

    case type
    when :app
      self.two_factor_configured_with?(:app) && # if configured & verification failed but would suceeded if we allowed duplicate OTPs
      !self.two_factor_verify_app_otp(otp) && self.two_factor_app_totp.verify(otp, drift_ahead: TwoFactorCredential::ALLOWABLE_DRIFT, drift_behind: TwoFactorCredential::ALLOWABLE_DRIFT)
    when :sms
      self.two_factor_configured_with?(:sms) &&
      !self.two_factor_verify_sms_otp(otp) && self.two_factor_sms_totp.verify(otp, drift_ahead: TwoFactorCredential::ALLOWABLE_DRIFT, drift_behind: TwoFactorCredential::ALLOWABLE_DRIFT)
    else
      false
    end
  end

  # Key for SMS OTP timing hash. Public for testing.
  def sms_timing_key(otp, secret)
    otp = sprintf("%06d", otp) if otp.is_a?(Integer)
    hash = Digest::SHA256.hexdigest "#{otp}|#{secret}|#{GitHub::TwoFactorAuthentication.otp_salt(:app, 1)}"
    "#{self.id}|#{hash}"
  end

  # Record this OTP and the time we're sending it.
  #
  # otp     - The OTP we sent.
  # receipt - A GitHub::SMS::Receipt.
  #
  # Returns nothing.
  def record_outstanding_sms_otp(otp, receipt, callsite)
    return unless self.two_factor_primary_sms_registration?

    provider = receipt.provider.provider_name

    GitHub.dogstats.increment "two_factor_credential", tags: ["action:sms_timing_sent", "provider:#{provider}", "country_code:#{GitHub::TwoFactorAuthentication.sms_country_code(self.two_factor_sms_number)}", "callsite:#{callsite}"]
    self.two_factor_primary_sms_registration.instrument_send_primary_sms(message_id: receipt.message_id, provider_name: provider)

    key = sms_timing_key(otp, self.two_factor_primary_sms_registration.encrypted_otp_secret)
    OtpSmsTiming.record_outstanding(key, provider, self.id)
  end

  # Record that we've received an OTP.
  def resolve_outstanding_sms_otp(otp)
    return unless self.two_factor_primary_sms_registration?
    sms_registration = self.two_factor_primary_sms_registration

    key = sms_timing_key(otp, sms_registration.encrypted_otp_secret)
    if timing = OtpSmsTiming.by_timing_key(key)
      provider = timing.provider
      time = timing.created_at
      OtpSmsTiming.resolve(timing.id)
      diff = ((Time.now - Time.at(time)).to_f * 1000).to_i
      GitHub.dogstats.timing "two_factor_credential.sms_timing", diff, tags: ["provider:#{provider}", "country_code:#{GitHub::TwoFactorAuthentication.sms_country_code(self.two_factor_sms_number)}", "store:mysql"]
      GitHub.dogstats.increment "two_factor_credential", tags: ["action:sms_timing_resolved", "provider:#{provider}", "country_code:#{GitHub::TwoFactorAuthentication.sms_country_code(self.two_factor_sms_number)}"]

      if provider != self.two_factor_sms_provider
        tags = ["from:#{self.two_factor_sms_provider}", "to:#{provider}", "action:resolve_outstanding_sms_otp"]
        if sms_registration.update(sms_provider: provider)
          tags << "result:success"
        else
          tags << "result:failure"
        end
        GitHub.dogstats.increment "two_factor.switched_sms_provider", tags: tags
      end
    end
  end

  # Increment the daily rate limit counter for the SMS number and the user
  # if country code is in the HIGH_RISK_SMS_COUNTRY_CODES_MAP
  def sms_daily_rate_limit_increment(sms_number)
    return unless sms_number_included_in_high_risk_country_code_map? sms_number
    ActiveRecord::Base.connected_to(role: :writing) do
      GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:sms_daily_rate_limit"])
      GitHub::Authentication::KV.store.increment(
        sms_daily_rate_limit_key(sms_number),
        expires: Time.current.utc.end_of_day,
        touch_on_insert: true,
      )

      GitHub::Authentication::KV.store.increment(
        user_daily_sms_rate_limit_key,
        expires: Time.current.utc.end_of_day,
        touch_on_insert: true,
      )
    end
  end

  # Updates `last_used_at` to the current time when the user successfully authenticates with an otp 2FA method
  # type - the type of otp credential used to complete 2FA: :sms or :app
  def update_otp_credential_last_used_at(type)
    # explicit write is nessesary here for the GHES edge case where API password auth is still supported on GETs
    ActiveRecord::Base.connected_to(role: :writing) do
      case type
      when :app
        T.must(self.totp_app_registration).update!(last_used_at: Time.now.utc)
      when :sms
        T.must(self.two_factor_primary_sms_registration).update!(last_used_at: Time.now.utc)
      end

      # we can't differentiate between here since backup sms uses the same secret when either app and sms are the primary configuration
      self.two_factor_backup_sms_registration&.update!(last_used_at: Time.now.utc) if self.two_factor_backup_sms_registration
    end
  end

  # Checks if the current SMS number is part of our high risk SMS country codes map
  #
  # sms_number - The SMS number to check
  #
  # Returns a boolean
  def sms_number_included_in_high_risk_country_code_map?(sms_number)
    country_code = GitHub::TwoFactorAuthentication.sms_country_code(sms_number)
    country_code && HIGH_RISK_SMS_COUNTRY_CODES_MAP.key?(country_code.to_sym)
  end

  private

  def sms_daily_rate_limit_key(sms_number)
    "sms_daily_rate_limit:#{sms_number}"
  end

  def user_daily_sms_rate_limit_key
    "user_daily_sms_rate_limit:#{self.id}"
  end

  # Checks if the current SMS number has reached the daily limit of OTPs
  #
  # sms_number - The SMS number to check
  #
  # Returns a boolean
  def sms_number_at_daily_limit?(sms_number)
    return false unless sms_number_included_in_high_risk_country_code_map? sms_number
    key = sms_daily_rate_limit_key(sms_number)
    country_code = GitHub::TwoFactorAuthentication.sms_country_code(sms_number)
    limit = HIGH_RISK_SMS_COUNTRY_CODES_MAP[country_code.to_sym]
    current_count = GitHub::Authentication::KV.store.get(key).value { 0 }.to_i
    # The current_count should never be greater than the limit, but just in case we'll block it
    current_count >= limit
  end

  # Checks if the current user has reached the daily limit of SMS messages
  #
  # sms_number - The SMS number to check the country code of
  #
  # Returns a boolean
  def user_at_daily_sms_limit?(sms_number)
    return false unless sms_number_included_in_high_risk_country_code_map? sms_number
    country_code = GitHub::TwoFactorAuthentication.sms_country_code(sms_number)
    limit = self.spammy? ? SPAMMY_USER_SMS_LIMIT : HIGH_RISK_SMS_COUNTRY_CODES_MAP[country_code.to_sym]
    current_count = GitHub::Authentication::KV.store.get(user_daily_sms_rate_limit_key).value { 0 }.to_i
    # The current_count should never be greater than the limit, but just in case we'll block it
    current_count >= limit
  end

  def matches_spammy_reasons_for_restriction?
    self.spammy && SUSPICIOUS_SMS_SPAMMY_REASON_PATTERNS.any? do |pattern|
      return true unless (self.spammy_reason =~ pattern).nil?
    end
    false
  end

  # Checks if the current user is spammy and the country code is in the high risk SMS country codes map
  # Lets only block countries that are super high risk, if we block all high risk countries, we will block too many users - and support can see an increase in tickets
  #
  # sms_number - The SMS number to check the country code of
  #
  # Returns a boolean
  def user_is_spammy_and_high_risk_country_code?(sms_number)
    return false unless self.spammy?
    return false unless sms_number_included_in_high_risk_country_code_map? sms_number

    # We know the user is spammy, so we can directly check if the sms number is in the high risk country code map
    if self.feature_enabled?(:enforce_sms_restriction_for_spammy_users_and_all_high_risk_countries)
      true
    else
      # We shouldn't block all high risk countries right away, since that can disrupt a lot of legitimate users
      # Lets only block countries that are super high risk, but we can always enable the feature flag to block all high risk countries
      high_risk_fraud_countries = HIGH_RISK_SMS_COUNTRY_CODES_MAP.select { |_, val| val == 5 }
      country_code = GitHub::TwoFactorAuthentication.sms_country_code(sms_number)
      country_code_in_high_risk_fraud_country = high_risk_fraud_countries.key?(country_code.to_sym)
      # Incrementing a dogstat here to track how many users are in super high risk countries vs high risk countries
      # This can give us an idea on how many users we could block if we decide to block all high risk countries
      GitHub.dogstats.increment("sms.spammy_high_risk_country_code", tags: ["country_code:#{country_code}", "blocked:#{country_code_in_high_risk_fraud_country}"])
      country_code_in_high_risk_fraud_country
    end
  end

  def two_factor_sms_backup_provider_data_key
    "TwoFactorSMSFallbackProvider:#{T.must(self.two_factor_credential).id}"
  end

  def two_factor_sms_backup_provider_data
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:2fa_registrations"])
    data = GitHub::Authentication::KV.store.get(two_factor_sms_backup_provider_data_key).value { "{}" }
    # The KV block value is only returned in case of an error. If the key is
    # simply expired that isn't considered an error and will return `nil`.
    data ||= "{}"
    data = JSON.parse(data).symbolize_keys
  end

  def set_two_factor_sms_backup_provider_data(new_provider)
    GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:2fa_registrations"])
    kv_success = GitHub::Authentication::KV.store.try_set(
      two_factor_sms_backup_provider_data_key,
      { provider: new_provider.provider_name }.to_json,
      expires: 10.minutes.from_now,
    )
    unless kv_success
      GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :set_two_factor_sms_backup_provider_data, action: :set })
    end
  end

  def record_sms_otp_success
    ActiveRecord::Base.connected_to(role: :writing) do
      reg = self.two_factor_primary_sms_registration
      return unless reg

      if reg.total_otp_success_count < UINT_MAX
        reg.total_otp_success_count += 1
      end
      reg.last_otp_success_at = Time.now.utc
      reg.consecutive_missed_otp_count = 0
      unless reg.save
        GitHub.dogstats.increment("record_sms_otp_success.failure")
      end
    end
  end

  def record_sms_otp_sent(use_alternate_provider, callsite, completed_captcha)
    ActiveRecord::Base.connected_to(role: :writing) do
      reg = self.two_factor_primary_sms_registration
      return unless reg

      if reg.total_otp_sent_count < UINT_MAX
        reg.total_otp_sent_count += 1
      end
      reg.last_otp_sent_at = Time.now.utc
      unless reg.save
        GitHub.dogstats.increment("record_sms_otp_sent.failure", tags: [
          "use_alternate_provider:#{use_alternate_provider}",
          "callsite:#{callsite}",
          "completed_captcha:#{completed_captcha}",
        ])
      end
    end
  end
end
