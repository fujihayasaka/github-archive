# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class YearOldRecoveryCodes < ScheduledBaseCheck

    INTERVAL = T.let(1.year, ActiveSupport::Duration)
    SNOOZE_INTERVAL = T.let(3.months, ActiveSupport::Duration)

    sig { returns(T::Boolean) }
    def should_show_notice?
      return false unless viewer.feature_flag_enabled?(:actionable_two_factor_security_checkup, default: false) &&
        viewer.two_factor_authentication_enabled? &&
        !viewer.dismissed_notice?(:year_old_recovery_codes, kv_store: GitHub::Authentication::KV.store)

      viewer.two_factor_credential.recovery_codes_unsaved_after_first_year
    end

    sig { returns(T::Boolean) }
    def can_snooze?
      true
    end

    sig { void }
    def snooze
      viewer.dismiss_notice(:year_old_recovery_codes, expires: SNOOZE_INTERVAL.from_now, kv_store: GitHub::Authentication::KV.store)
    end

    sig { params(user_ids: T::Set[Integer]).returns(T::Array[Integer]) }
    def self.find_eligible(user_ids)
      # 2FA registration created at over a year ago and
      # recovery codes have never been saved or haven't been saved since a year after enrollment
      TwoFactorCredential.where(user_id: user_ids).where("created_at < ? " \
        "AND (recovery_codes_last_downloaded_at IS NULL OR recovery_codes_last_downloaded_at < created_at + INTERVAL 1 YEAR) " \
        "AND (recovery_codes_last_printed_at IS NULL OR recovery_codes_last_printed_at < created_at + INTERVAL 1 YEAR)", INTERVAL.ago).pluck(:user_id)
    end
  end
end
