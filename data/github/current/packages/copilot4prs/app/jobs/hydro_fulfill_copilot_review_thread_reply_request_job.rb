# typed: strict
# frozen_string_literal: true

class HydroFulfillCopilotReviewThreadReplyRequestJob < HydroMessageJob
  include GitHub::Memoizer

  MAX_RESTRAINT_RETRIES = 5
  RESTRAINT_LOCK_KEY = T.let("hydro_fulfill_copilot_review_thread_reply_request_job".freeze, String)
  RESTRAINT_LOCK_TTL = T.let(5.minutes.to_i, Integer)
  RESTRAINT_LOCK_CONCURRENCY = 250

  queue_as :hydro_fulfill_copilot_review_thread_reply_request

  retry_on_dirty_exit
  retry_on CopilotAPI::UnauthorizedError, CopilotAPI::NetworkError, max_retries: 1 do |job, error|
    GitHub.dogstats.increment("copilot.code_review_thread_reply.persistence.retry_failed")

    job.review_thread_reply_generator&.log("retry failed: #{error}")
    job.submit_failed_review_thread_reply_error
  end

  retry_on GitHub::Restraint::UnableToLock, delay: :polynomially_longer, max_retries: MAX_RESTRAINT_RETRIES do |job, error|
    GitHub.dogstats.increment("copilot.code_review_thread_reply.retries_exhausted")
    job.review_thread_reply_generator&.log("retries exhausted: #{error}")
    job.submit_failed_review_thread_reply_error
  end

  # Resolve the tenant for proxima so we can properly query for the users and repo.
  resolve_tenant_context do |message|
    Repositories::Public.resolve_tenant(id: message.dig(:repository, :id))
  end

  # Public: if message is requesting a thread reply from Copilot, this job will
  # generate a thread reply from Copilot.
  sig { void }
  def perform
    log("start HydroFulfillCopilotReviewThreadReplyRequestJob")

    @requestor = T.let(User.find_by(id: message.dig(:actor, :id)), T.nilable(User))
    return unless @requestor.present?
    return unless FeatureFlag.vexi.enabled?(:ccr_chat_with_comments, @requestor, default: false)

    @repo = T.let(nil, T.nilable(Repository))
    @repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(message.dig(:repository, :id)), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: message.dig(:repository, :id))
    end
    return unless @repo.present?
    return unless FeatureFlag.vexi.enabled?(:ccr_chat_with_comments, @repo, default: false)

    @comment = T.let(PullRequestReviewComment.find_by(id: message.dig(:pull_request_review_comment, :id)), T.nilable(PullRequestReviewComment))
    @pull = T.let(PullRequest.find_by(id: message.dig(:pull_request, :id)), T.nilable(PullRequest))
    @thread = T.let(PullRequestReviewThread.find_by(id: message.dig(:pull_request_review_thread, :id)), T.nilable(PullRequestReviewThread))
    @pr_review = T.let(PullRequestReview.find_by(id: message.dig(:pull_request_review, :id)), T.nilable(PullRequestReview))
    return unless @comment.present? && @pull.present? && @thread.present? && @pr_review.present?

    code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: @requestor, current_repository: @repo)

    if code_review_access.can_create_review_request?
      log("actor has proper access")
    else
      log("actor cannot create review request")
      submit_failed_review_thread_reply_error
      return
    end


    with_global_lock do
      log("start CodeReviewThreadReplyGenerator")

      if review_thread_reply_generator.generate
        T.must(@thread.pull_request_review).notify_socket_subscribers
        log("finish CodeReviewThreadReplyGenerator")
      else
        log("review thread reply generation failed")
        submit_failed_review_thread_reply_error
      end
    end
  rescue GitHub::Restraint::UnableToLock, CopilotAPI::NotFoundError, CopilotAPI::UnauthorizedError, CopilotAPI::NetworkError => err
    Failbot.report(err)

    # For retryable errors, re-raise so the job is retried.
    # For non-retryable errors, re-raise so we get a `github.hydro_message_job.error` metric.
    raise err
  rescue CopilotAPI::QuotaExceededError => err
    GitHub.dogstats.increment("copilot.code_review_thread_reply.quota_exceeded")
  rescue StandardError => err # rubocop:todo Lint/RescueException
    Failbot.report(err)

    # Any errors we get that we do not retry, we need to clean up and return a thread comment saying that we failed.
    log(err.message)
    submit_failed_review_thread_reply_error
  end

  sig { void }
  def submit_failed_review_thread_reply_error
    review_thread_reply_generator.submit_failed_review_thread_reply
  end

  sig { returns(PullRequests::Copilot::CodeReview::ThreadReplyGenerator) }
  memoize def review_thread_reply_generator
    PullRequests::Copilot::CodeReview::ThreadReplyGenerator.new(
      comment: T.must(@comment),
      pull: T.must(@pull),
      repo: T.must(@repo),
      requestor: T.must(@requestor),
      review: T.must(@pr_review),
      thread: T.must(@thread),
    )
  end

  private

  sig { params(message: String).void }
  def log(message)
    GitHub.logger.info("hydro_fulfill_copilot_review_thread_reply_request_job: #{message}",
      "gh.repository.id" => @repo&.name_with_display_owner,
      "gh.user.id" => @requestor&.id,
      "gh.user.login" => @requestor&.display_login,
      "gh.pull_request_review_thread.id" => @thread&.id,
      "gh.pull_request.id" => @pull&.id,
      "gh.pull_request.url" => @pull&.url,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id]
    )
  end

  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def with_global_lock(&block)
    restraint = GitHub::Restraint.new
    restraint.lock!(RESTRAINT_LOCK_KEY, RESTRAINT_LOCK_CONCURRENCY, RESTRAINT_LOCK_TTL) do
      block.call
    end
  end
end
