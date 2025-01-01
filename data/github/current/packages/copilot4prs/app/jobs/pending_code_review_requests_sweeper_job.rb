# typed: true
# frozen_string_literal: true

# This job runs on a schedule and submits failed reviews for copilot review requests
# if request is more than 10 minutes old
class PendingCodeReviewRequestsSweeperJob < BatchedJob
  queue_as :pending_code_review_requests_sweeper
  schedule interval: 10.minutes, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(args: T.untyped, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(ActiveRecord::Relation) }
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    ReviewRequest.pending.not_dismissed
      .where("reviewer_id = ? AND created_at < ? AND id > ?", app.bot.id, 10.minutes.ago, offset_item_id)
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
      next if pull.state != :open
      next unless pending_request.pending?

      ActiveRecord::Base.connected_to(role: :writing) do
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
      end
    end
  end

  sig { params(message: String,  pull: ::PullRequest).void }
  def log(message, pull)
    GitHub.logger.info("pending_code_review_requests_sweeper: #{message}",
      "gh.repository.id" => pull.repository&.name_with_display_owner,
      "gh.pull_request.id" => pull.id,
      "gh.pull_request.url" => pull.url,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id]
    )
  end
end
