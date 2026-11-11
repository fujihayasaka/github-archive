# typed: strict
# frozen_string_literal: true

class HydroProcessCopilotStatusUpdateJob < HydroMessageJob
  include GitHub::Memoizer

  CURRENT_JOBS = 1
  LOCK_TTL = T.let(5.minutes.to_i, Integer)
  LOCK_KEY = "CopilotCodeReviewResponse_%{pull_id}_%{pull_head_sha}"
  queue_as :hydro_process_copilot_status_update

  retry_on_dirty_exit

  sig { void }
  def perform
    log("start HydroProcessCopilotStatusUpdateJob")

    # If we don't have a pull request or repo, we can't proceed
    return unless pull && repo

    # Here we use the same lock key as the review response job to prevent race conditions
    # with the finalized review (or other concurrent reviews).
    lock_key = LOCK_KEY % { pull_id: T.must(pull).id, pull_head_sha: T.must(pull).head_sha }

    restraint = GitHub::Restraint.new
    restraint.lock!(lock_key, CURRENT_JOBS, LOCK_TTL) do
      status_type = message[:status_type].presence || :UNKNOWN_STATUS_TYPE

      # Handle different status types with appropriate actions
      case status_type
      when :FAILURE, :TIMEOUT
        handle_failure_status
      when :UNKNOWN_STATUS_TYPE, :SUCCESS, :CANCELLED, :PARTIAL_SUCCESS
        log("received ignored status type: #{status_type}")
      else
        log("received unexpected status type: #{status_type}")
      end
    end

    log("end HydroProcessCopilotStatusUpdateJob")
  rescue GitHub::Restraint::UnableToLock => err
    log("duplicate job detected for sha #{T.must(pull).head_sha}")
    Failbot.report(err)
  end

  private

  sig { params(message: String).void }
  def log(message)
    GitHub.logger.info("hydro_process_copilot_status_update_job: #{message}",
      "gh.repository.id" => repo&.id,
      "gh.repository.nwo" => repo&.name_with_display_owner,
      "gh.pull_request.id" => pull&.id,
      "gh.pull_request.url" => pull&.url,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => request_id,
      "gh.code_review.job_id" => code_review_job_id,
    )
  end

  sig { void }
  def handle_failure_status
    return unless bot
    return unless review_request
    return unless FeatureFlag.vexi.enabled?(:copilot_code_review_post_failure_message, repo, default: true)

    p = T.must(pull)

    # Dismiss pending requests for closed/merged PRs - these reviews will never be needed
    if p.state != :open
      dismiss_for_closed_pr
      return
    end

    submit_failed_review
  end

  sig { void }
  def submit_failed_review
    p = T.must(pull)
    b = T.must(bot)

    ActiveRecord::Base.connected_to(role: :writing) do
      begin
        review = p.pending_review_for(user: b, head_sha: p.head_sha)
        review.variant_type = T.must(PullRequestReview.variant_types[:copilot])
        review.body = PullRequests::Copilot::CodeReviewCreator::ERROR_COMMENTS
        review.comment!
        if review.commented?
          GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review", tags: ["success:true"])
          log("successfully submitted failed review")
        else
          GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review", tags: ["success:false"])
          log("error submitting failed review")
        end
      rescue => e
        GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review", tags: ["success:false", "error:true"])
        log("exception submitting failed review: #{e.class}: #{e.message}")
      ensure
        dismiss_if_still_pending
      end
    end
  end

  # Dismiss pending requests for closed/merged PRs - these reviews will never be needed
  sig { void }
  def dismiss_for_closed_pr
    rr = review_request
    return unless rr

    ActiveRecord::Base.connected_to(role: :writing) do
      rr.reload
      return unless rr.pending? && !rr.dismissed?

      rr.dismiss
      rr.save!
      GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review.dismissed_closed_pr")
      log("dismissed pending request for closed/merged PR")
    end
  rescue => e
    GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review.dismissed_closed_pr_error")
    log("error dismissing pending request for closed/merged PR: #{e.class}: #{e.message}")
  end

  # Dismiss the pending request if it was not fulfilled by the review submission.
  # This handles cases where the review could not be persisted (e.g., owner-locked
  # repositories where validations prevent the save) but the request still needs
  # to be resolved.
  sig { void }
  def dismiss_if_still_pending
    rr = review_request
    return unless rr

    rr.reload
    return unless rr.pending? && !rr.dismissed?

    rr.dismiss
    rr.save!
    GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review.fallback_dismiss")
    log("dismissed unfulfilled pending request as fallback")
  rescue => e
    GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review.fallback_dismiss_error")
    log("error dismissing pending request as fallback: #{e.class}: #{e.message}")
  end

  sig { returns(T.nilable(Bot)) }
  memoize def bot = Apps::Privileged.integration(:copilot_pull_request_reviewer)&.bot

  sig { returns(T.nilable(ReviewRequest)) }
  memoize def review_request = pull&.review_requests_pending&.find_by(reviewer: bot)

  sig { returns(T.nilable(Repository)) }
  memoize def repo = pull&.repository

  sig { returns(T.nilable(PullRequest)) }
  memoize def pull = PullRequest.find_by(id: message.dig(:metadata, :pull_request_id))

  sig { returns(T.nilable(String)) }
  memoize def request_id = headers[CopilotAPI::GITHUB_REQUEST_ID_HEADER]

  sig { returns(T.untyped) }
  def code_review_job_id = message.dig(:metadata, :review_id)
end
