# typed: true
# frozen_string_literal: true

module GitHub
  class TwoFactorAuthentication
    class NoSecretConfigured < StandardError; end
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

    def self.recovery_salt(version)
      return "" if GitHub.single_or_multi_tenant_enterprise?
      raise NoSecretConfigured, "No secrets configured to mix into recovery_code secrets" if GitHub.recovery_code_salts.empty?
      raise NoSecretConfigured, "2FA recovery_code secret salt version missing: #{version}" unless GitHub.recovery_code_salts[version.to_s]
      GitHub.recovery_code_salts[version.to_s]
    end

    # :sms verifies against the latest salt unless otherwise specified
    def self.otp_salt(type, salt_version)
      return "" if GitHub.single_or_multi_tenant_enterprise?
      Failbot.report(NoSecretConfigured.new("No secrets configured for invalid salt type: #{type}")) if ![:app, :sms].include?(type)
      if type == :sms
        raise NoSecretConfigured, "No secrets configured to mix into otp secrets" if GitHub.sms_otp_salts.empty?
        return GitHub.sms_otp_salts.last if salt_version.nil?
        raise NoSecretConfigured, "2FA otp secret salt version missing: #{salt_version}" unless GitHub.sms_otp_salts[salt_version]
        GitHub.sms_otp_salts[salt_version]
      else # app and 'generic' type authentication (legacy support) are both app authentication
        raise NoSecretConfigured, "No secrets configured to mix into otp secrets" if GitHub.app_otp_salts.empty?
        raise NoSecretConfigured, "2FA otp secret salt version missing: #{salt_version}" unless GitHub.app_otp_salts[salt_version.to_s]
        GitHub.app_otp_salts[salt_version.to_s]
      end
    end

    # Return the mashed shared secret. This is actually the real,
    # 32 byte string that we send to the user as a shared secret. It is
    # generated based on the two-factor secret we keep in the database and
    # a salt loaded from the environment.
    #
    # WARNING: Display this to the user **only once**, when dual factor
    # authentication is activated.
    def self.mashed_secret(type, secret, salt_version)
      salt = GitHub::TwoFactorAuthentication.otp_salt(type, salt_version)
      mashed = "#{secret}:#{salt}"
      OpenSSL::Digest::SHA1.digest(mashed).each_byte.map do |b| # rubocop:disable GitHub/InsecureHashAlgorithm
        ROTP::Base32::CHARS[b % 32]
      end.take(SECRET_LENGTH).join
    end

    def self.totp(type, secret, salt_version)
      return nil unless secret
      ROTP::TOTP.new(mashed_secret(type, secret, salt_version), issuer: GitHub.flavor)
    end

    def self.verify_otp(type, otp, secret, salt_version, cache_key_id)
      totp = totp(type, secret, salt_version)
      GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:verify_otp"])
      last_otp_at = GitHub::Authentication::KV.store.get(otp_cache_key(cache_key_id)).value { nil }&.to_i
      verified_at_or_fail = verify_at_or_fail(type, otp, secret, salt_version, last_otp_at)
      if last_otp_at
        # last_otp_at is set if the user verified an OTP in the last 'TwoFactorCredential::LAST_OTP_TTL' (~3 minutes)
        last_otp_within_1_min = Time.at(last_otp_at) > 1.minute.ago
        duplicate_otp = last_otp_at == verify_at_or_fail(type, otp, secret, salt_version)
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

      failure_reason = self.otp_failure_reason(type, otp, secret, salt_version, duplicate_otp) if !verified_at_or_fail
      self.log_result(:otp_2fa, verified_at_or_fail, failure_reason)
      !!verified_at_or_fail
    end

    def self.verify_otp_for_setup(type, otp, secret, salt_version)
      verify_otp_allow_reuse(type, otp, secret, salt_version, nil)
    end

    # Was this OTP valid at any time, 15 minutes in either direction from now.
    #
    # otp  - A string OTP.
    # time - The time to check around. (default Time.now)
    #
    # Returns true/false.
    def self.recently_valid_otp?(type, otp, secret, salt_version, time = Time.now)
      start = (time - 15.minutes).to_i
      stop  = (time + 15.minutes).to_i
      times = (start..stop).step(30)


      return true if times.any? { |t| otp == self.totp(type, secret, salt_version).at(t) }
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
    def self.otp_valid_timestamp(type, otp, secret, salt_version)
      time = 24.hours.from_now.to_i
      one_day_ago = 24.hours.ago.to_i

      until time < one_day_ago
        return Time.at(time) if otp == self.totp(type, secret, salt_version).at(time)
        time -= 30
      end

      nil
    end

    def self.sms_country_code(sms_number)
      return unless sms_number.present?
      if match = sms_number.match(GitHub::Messaging::PHONE_NUMBER_PARTS_REGEX)
        match[1]
      end
    end

    # Return a list of country names matching the given country code
    def self.sms_country_names_for_code(country_code)
      return [] unless country_code.present?

      GitHub::Messaging::COUNTRY_NAMES_BY_CODE["+#{country_code}"] || []
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
    def self.recovery_codes(recovery_secret, recovery_salt_version, amount = RECOVERY_CODE_TOTAL_COUNT)
      amount.times.map { |n| recovery_code(recovery_secret, recovery_salt_version, n) }
    end

    # Recovery codes with a hyphen in the middle to make them easier to read.
    #
    # Returns an Array of Strings.
    def self.formatted_recovery_codes(recovery_secret, recovery_salt_version)
      recovery_codes(recovery_secret, recovery_salt_version).map do |code|
        "#{code.slice(0, 5)}-#{code.slice(5, 5)}"
      end
    end

    # Return the nth recovery key for dual-factor authentication
    #
    # Recovery keys are by default 8 numeric characters long,
    # returned as strings.
    def self.recovery_code(recovery_secret, recovery_salt_version, n)
      recovery_salt = GitHub::TwoFactorAuthentication.recovery_salt(recovery_salt_version)
      mash = "#{recovery_secret}:#{n}:#{recovery_salt}"
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
    def self.provisioning_url_for_authenticator_app(secret, app_salt_version, user_login)
      if GitHub.enterprise? || !Rails.env.production?
        totp(:app, secret, app_salt_version).provisioning_uri("#{GitHub.urls.host_name}/#{user_login}")
      else
        totp(:app, secret, app_salt_version).provisioning_uri(user_login)
      end
    end

    def self.verify_otp_allow_reuse(type, otp, secret, salt_version, cache_key_id)
      verified_at_or_fail = verify_at_or_fail(type, otp, secret, salt_version)
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
      failure_reason = self.otp_failure_reason(type, otp, secret, salt_version, false) if !verified_at_or_fail
      self.log_result(:otp_2fa, !!verified_at_or_fail, failure_reason)
      !!verified_at_or_fail
    end
    private_class_method :verify_otp_allow_reuse

    # This method verifies app OTP once and sms OTP against all possible active salts
    # last_otp_at must be set to produce a verification failure on duplicate OTP usage
    def self.verify_at_or_fail(type, otp, secret, salt_version, last_otp_at = nil)
      if type == :sms
        (0...GitHub.sms_otp_salts.length).each do |index|
          verified_at_or_fail = totp(type, secret, index).verify(otp, drift_ahead: TwoFactorCredential::ALLOWABLE_DRIFT, drift_behind: TwoFactorCredential::ALLOWABLE_DRIFT, after: last_otp_at)
          return verified_at_or_fail if verified_at_or_fail
        end
      end

      totp(type, secret, salt_version).verify(otp, drift_ahead: TwoFactorCredential::ALLOWABLE_DRIFT, drift_behind: TwoFactorCredential::ALLOWABLE_DRIFT, after: last_otp_at)
    end
    private_class_method :verify_at_or_fail

    def self.otp_cache_key(cache_key_id)
      "#{OTP_CACHE_KEY_PREFIX}#{cache_key_id}"
    end
    private_class_method :otp_cache_key

    def self.otp_failure_reason(type, otp, secret, salt_version, duplicate_otp)
      failure_reason = if duplicate_otp
        :duplicate_otp
      else
        self.recently_valid_otp?(type, otp, secret, salt_version) ? :expired_otp : :invalid_otp
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
