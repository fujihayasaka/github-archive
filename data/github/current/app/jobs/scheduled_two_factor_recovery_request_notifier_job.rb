# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ScheduledTwoFactorRecoveryRequestNotifierJob < ApplicationJob
  queue_as :zendesk

  # This job is stateless and should be retried if a worker is killed.
  retry_on_dirty_exit

  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  BATCH_LIMIT = 1_000

  def perform
    recovery_requests =
      TwoFactorRecoveryRequest.ready_for_review.limit(BATCH_LIMIT)

    return if recovery_requests.empty?

    to_review = []
    to_automate = []
    recovery_requests.each do |req|
      begin
        # Review happens for all requests as UI aspects are dependent upon it.
        review = TwoFactorRecoveryRequestReview.new(req)
        ActiveRecord::Base.connected_to(role: :writing) do
          review.perform
        end

        # This flag needs to remain in place as a failsafe
        # In the event that some form of attack is formulated
        # This allows the authentication team to force manual
        # review of all cases
        if GitHub.flipper[:phoenix_two_factor_lockout_request_flow].enabled?(req.user)
          unless review.review_required?
            to_automate.push(req)
            next
          end
        end

        to_review.push([req, review])
      rescue TwoFactorRecoveryRequestReview::TemporarilyUnavailableError => e
        GitHub.dogstats.increment("two_factor_recovery_request_review.temporarily_unavailable")
        next
        # do not mark for automation or manual review, leave request to be retried later
      end
    end

    to_automate.each { |request| TwoFactorRecoveryRequestAutomatedApprovalJob.perform_later(request) } if to_automate.present?

    zendesk_ticket_user_ids = []

    to_review.each do |request, review|
      user_id = request.user_id

      next if zendesk_ticket_user_ids.include?(user_id)

      result = submit_zendesk_ticket(user_id, request, review)

      next unless result

      zendesk_ticket_user_ids.push(user_id)
      ActiveRecord::Base.connected_to(role: :writing) do
        request.update!(staff_review_requested_at: Time.now)
      end
      cleanup_other_requests(request.user, request)
    end unless to_review.empty?
  end

  private

  def submit_zendesk_ticket(user_id, request, review)
    locked_out_user = User.find_by(id: user_id)

    return false unless locked_out_user.present?

    email = locked_out_user.type == "User" ? locked_out_user.primary_user_email&.email : nil
    login = locked_out_user.login
    name = locked_out_user.profile&.name

    custom_fields = {
      GitHub.zendesk_fields[:business_plus]   => locked_out_user.business_plus?,
      GitHub.zendesk_fields[:login]           => login,
      GitHub.zendesk_fields[:plan]            => locked_out_user.plan.name,
      GitHub.zendesk_fields[:user_spammy]     => locked_out_user.spammy?,
      GitHub.zendesk_fields[:user_suspended]  => locked_out_user.suspended?,
    }

    subject = "Account request completed"
    body = zendesk_ticket_body(locked_out_user, request, review)

    tags = ["automated-2fa-recovery"]

    CreateZendeskTicket.perform_later(
      name.presence || login,
      email.presence || "accountrecovery@noreply.github.com",
      subject,
      body,
      brand_id: GitHub.zendesk_brand_id,
      tags: tags,
      custom_fields: custom_fields,
    )

    true
  end

  def zendesk_ticket_body(user, request, review)
    staff_review_url_general = "#{GitHub.stafftools_url}/stafftools/users/#{user.login}"
    staff_review_url_security = "#{GitHub.stafftools_url}/stafftools/users/#{user.login}/security"

    body = <<~BODY
      #{user.login} has submitted an account recovery request to disable two-factor authentication on their account.

      Please review the details in stafftools:

      #{staff_review_url_general}
      #{staff_review_url_security}

      Recovery request context:
      #{request.secondary_evidence_method} '#{request.secondary_evidence_identifier}' was verified by #{user.login}.

      Request id: #{request.id}
    BODY

    if GitHub.flipper[:recovery_without_password_flagging].enabled?(user)
      body << "Request type: #{review.request_type == "password_reset" ? "password reset account recovery (without password)" : "login 2FA account recovery (with password)"}"
    end

    body <<
    "\nReview type: #{review.type}" \
    "\nReview reason: #{review.reason}" \
    "\nReview message: #{review.message}"

    body
  end

  def cleanup_other_requests(user, request)
    other_requests = user.two_factor_recovery_requests.where.not(id: request.id)
    GitHub.dogstats.distribution("two_factor_account_recovery.cleanup_other_requests", other_requests.count) if other_requests.present?
    ActiveRecord::Base.connected_to(role: :writing) do
      other_requests.each do |r|
        r.instrument_ignore
        r.destroy
      end
    end
  end
end
