# typed: true
# frozen_string_literal: true

class GlobalNoticeNext
  class OneVerifiedEmailCheck < ScheduledBaseCheck

    SNOOZE_INTERVAL = T.let(1.month, ActiveSupport::Duration)

    sig { returns(T::Boolean) }
    def should_show_notice?
      return false if viewer.joined_too_recently_for_email_verification_reminder?
      # If a user cannot change their email, they should not see this notice
      return false unless viewer.change_email_enabled?
      return false unless viewer.feature_enabled?(:actionable_two_factor_security_checkup) &&
        !viewer.dismissed_notice?(:one_verified_email, kv_store: GitHub::Authentication::KV.store)

      # Show notice if user has exactly one verified email and it was verified more than a month ago
      viewer.add_additional_verified_emails_after_first_verified_email?
    end

    sig { returns(T::Boolean) }
    def can_snooze?
      true
    end

    sig { void }
    def snooze
      viewer.dismiss_notice(:one_verified_email, expires: SNOOZE_INTERVAL.from_now, kv_store: GitHub::Authentication::KV.store)
    end

    sig { params(user_ids: T::Set[Integer]).returns(T::Array[Integer]) }
    def self.find_eligible(user_ids)
      # Grab all users with exactly one verified email
      verified_emails = UserEmail.verified.where(user_id: user_ids).group(:user_id).having("count(*) = 1")
      # Only grab users whose one verified email was verified more than a month ago
      verified_emails.select { |email| email.verified_at < 1.month.ago }.pluck(:user_id)
    end
  end
end
