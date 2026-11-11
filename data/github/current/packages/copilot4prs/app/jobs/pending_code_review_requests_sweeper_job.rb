# typed: true
# frozen_string_literal: true

# This job runs on a schedule and submits failed reviews for copilot review requests
# if request is more than 15 minutes old
class PendingCodeReviewRequestsSweeperJob < BatchedJob
  queue_as :pending_code_review_requests_sweeper
  schedule interval: 10.minutes, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(args: T.untyped, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(ActiveRecord::Relation) }
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    ReviewRequest.pending.not_dismissed
      .where("reviewer_id = ? AND created_at < ? AND id > ?", app.bot.id, 15.minutes.ago, offset_item_id)
      .includes(pull_request: :user)
      .limit(BATCH_SIZE)
  end

  sig { params(batch: ActiveRecord::Relation, args: T.untyped, options: T.untyped).returns(T.untyped) }
  def process_batch(batch, *args, **options)
    app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    batch.each do |pending_request|
      pull = pending_request.pull_request
      next unless pull
      next unless pull.repository
      next unless FeatureFlag.vexi.enabled?(:pending_copilot_code_review_requests_sweeper, pull.repository, default: false)
      next unless pending_request.pending?

      # Dismiss pending requests for closed/merged PRs - these reviews will never be needed
      if pull.state != :open
        if FeatureFlag.vexi.enabled?(:pending_copilot_code_review_requests_sweeper_dismiss_closed, pull.repository, default: false)
          dismiss_for_closed_pr(pending_request, pull)
        end
        next
      end

      ActiveRecord::Base.connected_to(role: :writing) do
        begin
          review = pull.pending_review_for(user: app.bot, head_sha: pull.head_sha)
          review.variant_type = T.must(PullRequestReview.variant_types[:copilot])
          review.body = PullRequests::Copilot::CodeReviewCreator::ERROR_COMMENTS
          review.comment!
          if review.commented?
            GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review", tags: ["success:true"])
            log("successfully submitted failed review", pull)
          else
            GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review", tags: ["success:false"])
            log("error submitting failed review", pull)
          end
        rescue => e
          GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review", tags: ["success:false", "error:true"])
          log("exception submitting failed review: #{e.class}: #{e.message}", pull)
        ensure
          dismiss_if_still_pending(pending_request, pull)
        end
      end
    end
  end

  # Dismiss pending requests for closed/merged PRs - these reviews will never be needed
  sig { params(pending_request: ReviewRequest, pull: ::PullRequest).void }
  def dismiss_for_closed_pr(pending_request, pull)
    ActiveRecord::Base.connected_to(role: :writing) do
      pending_request.reload
      return unless pending_request.pending? && !pending_request.dismissed?

      pending_request.dismiss
      pending_request.save!
      GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review.dismissed_closed_pr")
      log("dismissed pending request for closed/merged PR", pull)
    end
  rescue => e
    GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review.dismissed_closed_pr_error")
    log("error dismissing pending request for closed/merged PR: #{e.class}: #{e.message}", pull)
  end

  # Dismiss the pending request if it was not fulfilled by the review submission.
  # This handles cases where the review could not be persisted (e.g., owner-locked
  # repositories where validations prevent the save) but the request still needs
  # to be resolved to avoid infinite sweeper loops.
  sig { params(pending_request: ReviewRequest, pull: ::PullRequest).void }
  def dismiss_if_still_pending(pending_request, pull)
    pending_request.reload
    return unless pending_request.pending? && !pending_request.dismissed?

    pending_request.dismiss
    pending_request.save!
    GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review.fallback_dismiss")
    log("dismissed unfulfilled pending request as fallback", pull)
  rescue => e
    GitHub.dogstats.increment("copilot_code_review.submit_timed_out_review.fallback_dismiss_error")
    log("error dismissing pending request as fallback: #{e.class}: #{e.message}", pull)
  end

  sig { params(message: String,  pull: ::PullRequest).void }
  def log(message, pull)
    GitHub.logger.info("pending_code_review_requests_sweeper: #{message}",
      "gh.repository.id" => pull.repository&.id,
      "gh.repository.nwo" => pull.repository&.name_with_display_owner,
      "gh.pull_request.id" => pull.id,
      "gh.pull_request.url" => pull.url,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id]
    )
  end
end
