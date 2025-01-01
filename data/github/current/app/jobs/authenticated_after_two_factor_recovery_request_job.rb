# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class AuthenticatedAfterTwoFactorRecoveryRequestJob < ApplicationJob
  queue_as :two_factor_recovery

  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # This job is stateless and should be retried if a worker is killed.
  retry_on_dirty_exit

  # Set an upper bound just to be sure we never have issues with contrived edge
  # case scenarios.
  BATCH_SIZE = 1_000

  def perform
    recovery_requests = TwoFactorRecoveryRequest.where(
      "request_completed_at IS NOT NULL AND staff_review_requested_at IS NULL"
    ).limit(BATCH_SIZE)

    return if recovery_requests.empty?

    requesting_users_with_successful_login = []

    recovery_requests.each do |request|
      # we want to push all requests belonging to a user who signed in into the
      # array above - this guard check should ensure we don't duplicate the
      # mailer work for a user once they have been confirmed and sent the mailer
      next if requesting_users_with_successful_login.include?(request.user_id)

      completed_at = request.request_completed_at

      user = request.user
      new_sessions = user.present? ? user.sessions.where(["created_at > ?", completed_at]) : []

      next unless new_sessions.any?

      AccountRecoveryMailer.successful_login_detected(request.user).deliver_later

      requesting_users_with_successful_login.push(request.user_id)

      ActiveRecord::Base.connected_to(role: :writing) do
        cleanup_all_requests(user)
      end
    end
  end

  private

  def cleanup_all_requests(user)
    GitHub.dogstats.distribution("authenticated_after_two_factor_recovery_request.cleanup_requests", user.two_factor_recovery_requests.count) if user.two_factor_recovery_requests.present?
    user.two_factor_recovery_requests.each do |request|
      request.instrument_ignore
      request.destroy
    end
  end
end
