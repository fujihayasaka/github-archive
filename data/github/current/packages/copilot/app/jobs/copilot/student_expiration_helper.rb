# typed: strict
# frozen_string_literal: true

module Copilot
  # Shared helper for sending student coupon expiration warnings.
  # Used by both SubscriptionItemExpiredCheckJob and ExpiringStudentBatchedJob
  # to avoid duplicating the warning logic.
  module StudentExpirationHelper
    sig { params(user: ::User).void }
    def self.send_expiration_warning(user)
      GitHub.logger.info("Sending expiration warning for student", "gh.user.id" => user.id)
      CopilotFreeUserMailer
        .expiration_warning(user, Copilot::FreeUser::EXPIRATION_WARNING_DURATION.from_now)
        .deliver_later

      copilot_user = Copilot::User.new(user)
      coupon_code = copilot_user.user_object.coupon_redemption&.coupon&.code
      Copilot::Instrumenter.instrument_student_warned(copilot_user, coupon_code: coupon_code)
      GitHub.dogstats.increment("copilot.subscription_item_expired_check_job.expiry_warning_sent")
    end
  end
end
