# typed: true
# frozen_string_literal: true

module User::TwoFactorHolidayWarningDependency
  extend T::Helpers
  requires_ancestor { User }

  def should_see_two_factor_holiday_warning?
    # Users with the following conditions should be shown the holiday banner:
    # 1. User has 2FA enabled
    # 2. User has just TOTP app configured and (optional) GitHub Mobile
    # 3. User has not dismissed the warning already
    return false unless two_factor_authentication_enabled?
    return false if two_factor_backup_sms_number
    return false if two_factor_configured_with?(:sms)
    return false if has_registered_security_key? || has_registered_passkey?

    !two_factor_holiday_warning_dismissed?
  end

  def two_factor_holiday_warning_dismissed_key
    "user.two_factor_holiday_warning_dismissed.#{self.id}"
  end

  def two_factor_holiday_warning_dismiss!
    GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:2fa_holiday_warning"])
    kv_success = GitHub::Authentication::KV.store.try_set(two_factor_holiday_warning_dismissed_key, "true", expires: 32.days.from_now)
    unless kv_success
      GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :holiday_warning_dismiss, action: :set })
    end
  end

  def clear_two_factor_holiday_warning_dismissed!
    begin
      GitHub.dogstats.increment("authn_kv", tags: ["action:delete", "callsite:2fa_holiday_warning"])
      GitHub::Authentication::KV.store.del(two_factor_holiday_warning_dismissed_key)
    rescue GitHub::KV::UnavailableError
      GitHub.dogstats.increment("kv_unavailable", tags: { service_owner: :account_login, callsite: :holiday_warning_clear, action: :del })
    end
  end

  def two_factor_holiday_warning_dismissed?
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:2fa_holiday_warning"])
    GitHub::Authentication::KV.store.get(two_factor_holiday_warning_dismissed_key).value { "false" } == "true"
  end
end
