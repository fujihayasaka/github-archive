# typed: true
# frozen_string_literal: true

module GitHub
  class TwoFactorAuthentication
    # The length, in base32 characters, of the shared secret we send
    # to the user.
    #
    # WARNING: DO NOT MODIFY. This needs to be 16 to be compatible
    # with the Google Authenticator app.
    SECRET_LENGTH = 16

    # The total amount of recovery codes we send to the user
    # for storage. 16 is a nice amount. Smaller is inconvenient for
    # the user; bigger is kind of redundant.
    RECOVERY_CODE_TOTAL_COUNT = 16

    # The length of each recovery code we send to the user, in
    # decimal digits. 8 is a nice amount because it can be
    # displayed as "XXXX XXXX". It could also be set to 10 and
    # displayed as "XXXX XX XXXXX".
    RECOVERY_CODE_LENGTH = 10

    # What a recovery code should look like
    RECOVERY_CODE_REGEX = /\A\h{#{RECOVERY_CODE_LENGTH}}\z/

    # OTP cache key string prefix
    OTP_CACHE_KEY_PREFIX = "totp::last_otp_at::"

    def self.recovery_code?(user_input)
      !!user_input.match(RECOVERY_CODE_REGEX)
    end

    def self.normalize_otp_from_params(params, allow_generic_otp_param: false, action:)
      if !params[:app_otp].nil?
        otp = TwoFactorCredential.normalize_otp(params[:app_otp])
        active_totp_type = :app
      elsif !params[:sms_otp].nil?
        otp = TwoFactorCredential.normalize_otp(params[:sms_otp])
        active_totp_type = :sms
      elsif allow_generic_otp_param && !params[:otp].nil?
        otp = TwoFactorCredential.normalize_otp(params[:otp])
        active_totp_type = nil
        GitHub.dogstats.increment("two_factor_auth.old_otp_param", tags: ["action:#{action}"])
      else
        otp = ""
        active_totp_type = nil
      end
      GitHub.dogstats.increment("normalize_otp_from_params.cannot_determine_active_type", tags: ["action:#{action}", "allow_generic_otp_param:#{allow_generic_otp_param}"]) if active_totp_type.nil?
      [otp, active_totp_type]
    end

    # Return the mashed shared secret. This is actually the real,
    # 32 byte string that we send to the user as a shared secret. It is
    # generated based on the two-factor secret we keep in the database and
    # a salt loaded from the environment.
    #
    # WARNING: Display this to the user **only once**, when dual factor
    # authentication is activated.
    def self.mashed_secret(secret)
      mashed = "#{secret}:#{GitHub.two_factor_salt}"
      OpenSSL::Digest::SHA1.digest(mashed).each_byte.map do |b| # rubocop:disable GitHub/InsecureHashAlgorithm
        ROTP::Base32::CHARS[b % 32]
      end.take(SECRET_LENGTH).join
    end

    def self.totp(secret)
      return nil unless secret
      ROTP::TOTP.new(mashed_secret(secret), issuer: GitHub.flavor)
    end

    def self.verify_otp(otp, secret, cache_key_id)
      GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:verify_otp"])
      last_otp_at = GitHub::Authentication::KV.store.get(otp_cache_key(cache_key_id)).value { nil }&.to_i
      verified_at_or_fail = totp(secret).verify(otp, drift_ahead: TwoFactorCredential::ALLOWABLE_DRIFT, drift_behind: TwoFactorCredential::ALLOWABLE_DRIFT, after: last_otp_at)
      if last_otp_at
        # last_otp_at is set if the user verified an OTP in the last 'TwoFactorCredential::LAST_OTP_TTL' (~3 minutes)
        last_otp_within_1_min = Time.at(last_otp_at) > 1.minute.ago
        duplicate_otp = last_otp_at == totp(secret).verify(otp, drift_ahead: TwoFactorCredential::ALLOWABLE_DRIFT, drift_behind: TwoFactorCredential::ALLOWABLE_DRIFT)
      end

      if verified_at_or_fail
        ActiveRecord::Base.connected_to(role: :writing) do
          begin
            GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:verify_otp"])
            GitHub::Authentication::KV.store.set(otp_cache_key(cache_key_id), verified_at_or_fail.to_s, expires: (TwoFactorCredential::LAST_OTP_TTL * 1.second).from_now)
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :two_factor_authentication_verify_otp, action: :set })
          end
        end
      end
      GitHub.dogstats.increment("authentication.2fa", tags: [
        verified_at_or_fail ? "result:success" : "result:failure", "allow_reuse:false",
        "otp_within_1_min:#{!!last_otp_within_1_min ? last_otp_within_1_min : "false"}",
        "otp_reuse:#{!!duplicate_otp ? duplicate_otp : "false"}"
      ])

      failure_reason = self.otp_failure_reason(otp, secret, duplicate_otp) if !verified_at_or_fail
      self.log_result(:otp_2fa, verified_at_or_fail, failure_reason)
      !!verified_at_or_fail
    end

    def self.verify_otp_for_setup(otp, secret)
      verify_otp_allow_reuse(otp, secret, nil)
    end

    # Was this OTP valid at any time, 15 minutes in either direction from now.
    #
    # otp  - A string OTP.
    # time - The time to check around. (default Time.now)
    #
    # Returns true/false.
    def self.recently_valid_otp?(otp, secret, time = Time.now)
      start = (time - 15.minutes).to_i
      stop  = (time + 15.minutes).to_i
      times = (start..stop).step(30)


      return true if times.any? { |t| otp == self.totp(secret).at(t) }
      false
    end

    # Finds the exact time an OTP was or will be valid, within 24 hours of now
    #
    # otp  - A string OTP
    #
    # Returns a tuple of [time, type], or [nil, nil] if it was not valid recently
    # This Time represents the beginning of the 30 second window the code would
    # have been generated in.  It does not account for clock skew we might allow.
    # The type is either :app (if valid via the app registration), :sms (if valid via the sms registration), or nil if the OTP was not valid recently with either registration.
    def self.otp_valid_timestamp(otp, secret)
      time = 24.hours.from_now.to_i
      one_day_ago = 24.hours.ago.to_i

      until time < one_day_ago
        return Time.at(time) if otp == self.totp(secret).at(time)
        time -= 30
      end

      nil
    end

    def self.sms_country_code(sms_number)
      return unless sms_number.present?
      if match = sms_number.match(GitHub::SMS::PHONE_NUMBER_PARTS_REGEX)
        match[1]
      end
    end

    # Return an array of two-factor recovery codes.
    #
    # WARNING: This array must  be given to the user **only once**,
    # when he activates dual factor authentication.
    #
    # By default we return 16 of these codes; they are one time use
    # only: once a code is used, it doesn't work anymore. They must
    # be used in consecutive order. Instruct the user to cross them
    # out as they are being used.
    #
    # If the user runs out of one-time keys, you can call
    # User#generate_two_factor_recovery! to generate 16 new keys.
    #
    # E.g.
    #
    #   ["01230123", "01230123", ...]
    #
    def self.recovery_codes(recovery_secret, amount = RECOVERY_CODE_TOTAL_COUNT)
      amount.times.map { |n| recovery_code(recovery_secret, n) }
    end

    # Recovery codes with a hyphen in the middle to make them easier to read.
    #
    # Returns an Array of Strings.
    def self.formatted_recovery_codes(recovery_secret)
      recovery_codes(recovery_secret).map do |code|
        "#{code.slice(0, 5)}-#{code.slice(5, 5)}"
      end
    end

    # Return the nth recovery key for dual-factor authentication
    #
    # Recovery keys are by default 8 numeric characters long,
    # returned as strings.
    def self.recovery_code(recovery_secret, n)
      mash = "#{recovery_secret}:#{n}:#{GitHub.two_factor_salt}"
      OpenSSL::Digest::SHA1.hexdigest(mash)[0, RECOVERY_CODE_LENGTH] # rubocop:disable GitHub/InsecureHashAlgorithm
    end

    # Produces the URI used by authenticator apps. e.g.
    #
    # otpauth://totp/GitHub:user?secret=<secret>&issuer=GitHub
    #
    # Produces separate URLs across enterprise and non-prod envs to prevent confusion.
    #
    # In Duo's UI:
    # dotcom: GitHub:<username>
    # non-prod/enterprise: GitHub[ Enterprise]:<hostname>/<username>
    def self.provisioning_url_for_authenticator_app(secret, user_login)
      if GitHub.enterprise? || !Rails.env.production?
        totp(secret).provisioning_uri("#{GitHub.urls.host_name}/#{user_login}")
      else
        totp(secret).provisioning_uri(user_login)
      end
    end

    def self.verify_otp_allow_reuse(otp, secret, cache_key_id)
      verified_at_or_fail = totp(secret).verify(otp, drift_ahead: TwoFactorCredential::ALLOWABLE_DRIFT, drift_behind: TwoFactorCredential::ALLOWABLE_DRIFT)
      # cache_key_id is nil for users who have not yet set up 2FA
      if cache_key_id
        # last_otp_at is nil if the user hasn't verified an OTP in the last 'TwoFactorCredential::LAST_OTP_TTL' (~3 minutes)
        GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:verify_otp_allow_reuse"])
        last_otp_at = GitHub::Authentication::KV.store.get(otp_cache_key(cache_key_id)).value { nil }&.to_i
        last_otp_within_1_min = last_otp_at && Time.at(last_otp_at) > 1.minute.ago
        duplicate_otp = last_otp_at && last_otp_at == verified_at_or_fail

        if verified_at_or_fail
          ActiveRecord::Base.connected_to(role: :writing) do
            GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:verify_otp_allow_reuse"])
            GitHub::Authentication::KV.store.set(otp_cache_key(cache_key_id), verified_at_or_fail.to_s, expires: (TwoFactorCredential::LAST_OTP_TTL * 1.second).from_now)
          end
        end
      end

      GitHub.dogstats.increment("authentication.2fa", tags: [
        verified_at_or_fail ? "result:success" : "result:failure", "allow_reuse:true",
        "otp_within_1_min:#{!!last_otp_within_1_min ? last_otp_within_1_min : "false"}",
        "otp_reuse:#{!!duplicate_otp ? duplicate_otp : "false"}"
      ])
      failure_reason = self.otp_failure_reason(otp, secret, false) if !verified_at_or_fail
      self.log_result(:otp_2fa, !!verified_at_or_fail, failure_reason)
      !!verified_at_or_fail
    end
    private_class_method :verify_otp_allow_reuse

    def self.otp_cache_key(cache_key_id)
      "#{OTP_CACHE_KEY_PREFIX}#{cache_key_id}"
    end
    private_class_method :otp_cache_key

    def self.otp_failure_reason(otp, secret, duplicate_otp)
      failure_reason = if duplicate_otp
        :duplicate_otp
      else
        self.recently_valid_otp?(otp, secret) ? :expired_otp : :invalid_otp
      end
    end
    private_class_method :otp_failure_reason

    def self.log_result(scenario, success, reason)
      GitHub::Authentication.logger.info({
        "code.namespace" => self.name,
        "gh.auth.attempt.type" => scenario,
        "gh.auth.result" => success ? "success" : "failure",
        "gh.auth.failure.type" => success ? nil : scenario,
        "gh.auth.failure.reason" => success ? nil : reason })
    end
    private_class_method :log_result
  end
end
