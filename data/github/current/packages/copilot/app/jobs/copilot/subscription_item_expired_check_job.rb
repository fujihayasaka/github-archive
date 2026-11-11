# typed: strict
# frozen_string_literal: true

module Copilot
  class SubscriptionItemExpiredCheckJob < CopilotJob
    retry_on_dirty_exit
    queue_as :copilot_edu_user_deactivation_job
    locked_by timeout: 20.minutes, key: DEFAULT_LOCK_PROC
    schedule interval: 24.hours, condition: -> { GitHub.copilot_for_individuals_enabled? }
    gate_with_feature_flag :copilot_subscription_item_expired_check_job
    exempt_from_tenant_context_requirement

    around_enqueue do |_job, block|
      block.call if GitHub.copilot_for_individuals_enabled? ## Don't run in proxima
    end

    # Background job for cancelling subscription items that are associated with expired coupon redemptions, specifically for students.
    #This is necessary because when a coupon redemption expires, we need to make sure to cancel any active subscriptions that were relying on that coupon for their validity.
    sig { params(user_id: T.nilable(Integer), scheduled: T::Boolean).void }
    def perform(user_id: nil, scheduled: false)
      GitHub.logger.with_named_tags("code.function" => "perform", "gh.copilot.user.id" => user_id) do
        # if we get a user id passed, we're gonna check if the coupon is still active
        if user_id.present?
          user = ::User.find_by(id: user_id)
          return unless user.present?
          copilot_user = Copilot::User.new(user)
          return unless copilot_user.edu_signup_enabled?
          return unless copilot_user.active_subscription_is_edu

          if copilot_user.has_valid_student_coupon?
            # seems unlikely? if we're here it's because the coupon expiration event fired or we're running the job on all expired student coupons
            GitHub.logger.info("User has EDU SKU and still has a valid coupon")
            GitHub.dogstats.increment("copilot.subscription_item_expired_check_job.coupon_still_valid", tags: ["scheduled:#{scheduled}"])
            return
          else
            GitHub.logger.info("User no longer has valid coupon, cancelling Copilot Student subscription")
            with_write do
              # we log and instrument in this method
              result = copilot_user.cancel_active_edu_subscription
              if result.ok? && result.value { false }
                GitHub.logger.info("Copilot Student SubscriptionItem cancelled, sending email")
                CopilotFreeUserMailer.expired(user).deliver_later
                GitHub.dogstats.increment("copilot.subscription_item_expired_check_job.subscription_cancelled", tags: ["scheduled:#{scheduled}"])
              end
            end
          end
        else # this means we're running a scheduled job
          GitHub.logger.info("Running scheduled check for expired educational coupons for Copilot Student users")
          check_all_expired_educational

          GitHub.logger.info("Running scheduled check for expiring educational coupons for Copilot Student users")
          check_all_expiring_educational
        end
      end
    end

    sig { void }
    def check_all_expiring_educational
      Copilot::ExpiringStudentBatchedJob.perform_later
    end

    sig { void }
    def check_all_expired_educational
      Copilot::ExpiredStudentBatchedJob.perform_later
    end

    private

    sig { params(user: ::User).void }
    def send_expiration_warning(user)
      Copilot::StudentExpirationHelper.send_expiration_warning(user)
    end
  end
end
