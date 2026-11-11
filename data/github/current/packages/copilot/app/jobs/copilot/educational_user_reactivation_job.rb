# typed: strict
# frozen_string_literal: true

module Copilot
  # EducationalUserReactivationJob attempts to reactivate Copilot for eligible educational
  # users by resubscribing them to Copilot Student.
  # Enqueued with a user id, it skips execution in multi-tenant enterprise
  # environments and for users who are ineligible based on spam, suspension,
  # deletion, enterprise management, or other Copilot-specific checks.
  class EducationalUserReactivationJob < CopilotJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
    locked_by timeout: 2.minutes, key: DEFAULT_LOCK_PROC
    queue_as :copilot_edu_user_reactivation_job
    gate_with_feature_flag :copilot_educational_user_reactivation_job
    exempt_from_tenant_context_requirement

    around_enqueue do |_job, block|
      block.call unless GitHub.multi_tenant_enterprise?
    end

    sig { params(user_id: Integer).void }
    def perform(user_id)
      GitHub.logger.with_named_tags("gh.user.id" => user_id) do
        user = ::User.find_by(id: user_id)

        if user.nil?
          GitHub.logger.info("User not found")
          GitHub.dogstats.increment("copilot.educational_user_reactivation_job.user_missing")
          return
        end

        unless can_proceed?(user)
          GitHub.logger.info("User cannot proceed")
          GitHub.dogstats.increment("copilot.educational_user_reactivation_job.cannot_proceed")
          return
        end

        GitHub.logger.info("Educational user can proceed with reactivation, resubscribing if possible")

        result = with_write { copilot_user(user).subscribe_educational }

        if result.ok?
          GitHub.logger.info("User successfully resubscribed to Copilot Student")
          GitHub.dogstats.increment("copilot.educational_user_reactivation_job.success")
        else
          handle_copilot_error(result.error)
          GitHub.dogstats.increment("copilot.educational_user_reactivation_job.failed")
        end
      end
    end

    private

    sig { params(user: ::User).returns(T::Boolean) }
    def can_proceed?(user)
      return false if user.spammy? || user.suspended? || user.deleted?
      return false if user.is_enterprise_managed?

      cp = copilot_user(user)

      return false unless cp.edu_signup_enabled?
      return false if cp.has_cfb_access?
      return false if cp.trade_restricted?

      blocked = with_write { cp.block_if_sharing_payment_method_with_other_blocked_users! }
      if blocked
        GitHub.logger.info("User is sharing a payment method with a blocked user, blocking user from Copilot access")
        cp.send_abuse_notification(details: "Attempted reinstatement from Copilot::EducationalUserReactivationJob but blocked due to shared payment method with blocked user(s)")
        return false
      end

      true
    end

    sig { params(user: ::User).returns(Copilot::User) }
    def copilot_user(user)
      @copilot_user ||= T.let(nil, T.nilable(Copilot::User))
      @copilot_user ||= Copilot::User.new(user)
    end
  end
end
