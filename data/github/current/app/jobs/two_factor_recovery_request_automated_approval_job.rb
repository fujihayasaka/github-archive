# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TwoFactorRecoveryRequestAutomatedApprovalJob < ApplicationJob
  queue_as :two_factor_recovery

  # This job is stateless and should be retried if a worker is killed.
  retry_on_dirty_exit

  retry_on ActiveRecord::RecordNotSaved, wait: 30.seconds, attempts: 3

  rescue_from(ActiveJob::DeserializationError) do |e|
    # Failing to find the record to be automated is not an error, we can skip it assuming it has been cleaned up intentionally based on other actions
    true if e.cause.is_a?(ActiveRecord::RecordNotFound) && e.cause.model == "TwoFactorRecoveryRequest"
  end

  def perform(request)
    return unless request.review_state == :ready_for_review
    review = TwoFactorRecoveryRequestReview.mget([request.id])
    return if review.empty? || review[request.id]["review_required"]
    user = request.user

    ActiveRecord::Base.connected_to(role: :writing) do
      request.approve(User.ghost)
    end

    GitHub.instrument("two_factor_account_recovery.staff_approve", user: user, reason: "Automated approval")

    GlobalInstrumenter.instrument("two_factor_account_recovery.updated",
      action_type: :STAFF_APPROVED,
      user: user,
      evidence_type: request.hydro_evidence_type,
    )

    GitHub.dogstats.increment(
      "two_factor_account_recovery.completed",
      tags: ["status:approved", "reason:automated_approval",
        "gh_mobile_two_factor_available:#{user.gh_mobile_auth_available?}",
        "u2f_available:#{user.u2f_registrations.any?}",
        "synced_u2f_available:#{user.u2f_registrations.where(backup_state: true).any?}"]
    )
  rescue ActiveRecord::RecordNotFound => error
    GitHub.dogstats.increment("two_factor_account_recovery.auto_approve_missing")
  rescue ActiveRecord::ActiveRecordError => error
    GitHub.logger.error({
      exception: error,
      "gh.job.name": self.class.name,
      "gh.catalog_service": "github/account_login",
      "gh.account_recovery.request.id": request&.id,
      "gh.account_recovery.request.review_state": request&.review_state
    })
    Failbot.report error
    raise
  end
end
