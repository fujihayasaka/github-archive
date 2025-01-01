# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class HydroFulfillCopilotReviewRequestJob < HydroMessageJob
  MAX_RESTRAINT_RETRIES = 5
  RESTRAINT_LOCK_KEY = T.let("hydro_fulfill_copilot_review_request_job".freeze, String)
  RESTRAINT_LOCK_TTL = T.let(5.minutes.to_i, Integer)
  CONCURRENCY_HIGH = 500
  CONCURRENCY_LOW = 250

  queue_as :hydro_fulfill_copilot_review_request

  retry_on_dirty_exit
  retry_on CopilotAPI::UnauthorizedError, CopilotAPI::NetworkError, max_retries: 1 do |job, error|
    GitHub.dogstats.increment("copilot.code_review.persistence.retry_failed")

    job.review_generator&.log("retry failed: #{error}")
    job.submit_failed_review_error
  end

  retry_on GitHub::Restraint::UnableToLock, delay: :polynomially_longer, max_retries: MAX_RESTRAINT_RETRIES do |job, error|
    GitHub.dogstats.increment("copilot.code_review.retries_exhausted")
    job.review_generator&.log("retries exhausted: #{error}")
    job.submit_failed_review_error
  end

  # Resolve the tenant for proxima so we can properly query for the users and repo.
  resolve_tenant_context do |message|
    Repositories::Public.resolve_tenant(id: message.dig(:repository, :id))
  end

  # Public: if message is requesting a review from Copilot, this job will
  # generate a review from Copilot.
  sig { void }
  def perform
    log("start HydroFulfillCopilotReviewRequestJob")

    @repo = T.let(Repository.find_by(id: message.dig(:repository, :id)), T.nilable(Repository))
    @pull = T.let(PullRequest.find_by(id: message.dig(:pull_request, :id)), T.nilable(PullRequest))
    @requestor = T.let(User.find_by(id: message.dig(:actor, :id)), T.nilable(User))

    # Don't trigger for unrequested review requests.
    return unless requested_or_rerequested?(message)
    log("passed requested or re-requested action check")

    # Only trigger when requesting Copilot for review.
    return unless copilot_review_request?(message)
    log("passed CCR bot requestor check")

    code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: @requestor, current_repository: @repo)
    unless code_review_access.can_create_review_request?
      log("actor cannot create review request")
      submit_failed_review_error
      return
    end
    log("actor has proper access")

    with_global_lock do
      log("start CodeReviewGenerator")
      unless review_generator.generate
        log("review generation failed")
        submit_failed_review_error
      end
      log("finish CodeReviewGenerator")
    end

  rescue GitHub::Restraint::UnableToLock, CopilotAPI::NotFoundError, CopilotAPI::UnauthorizedError, CopilotAPI::NetworkError => err
    Failbot.report(err)

    # For retryable errors, re-raise so the job is retried.
    # For non-retryable errors, re-raise so we get a `github.hydro_message_job.error` metric.
    raise err
  rescue CopilotAPI::QuotaExceededError => err
    GitHub.dogstats.increment("copilot.code_review.quota_exceeded")
    quota_exceeded_dismiss_review
  rescue StandardError => err # rubocop:todo Lint/GenericRescue
    Failbot.report(err)

    # Any errors we get that we do not retry, we need to clean up and return a review comment saying that we failed.
    log(err.message)
    submit_failed_review_error
  end

  sig { void }
  def submit_failed_review_error
    review_generator.submit_failed_review
  end

  sig { void }
  def quota_exceeded_dismiss_review
    review_generator.quota_exceeded_dismiss_review
  end

  sig { returns(PullRequests::Copilot::CodeReviewGenerator) }
  def review_generator
    return T.must(@review_generator) if defined?(@review_generator)
    # we have to assume that @pull is not nil here so that we can actually submit a failed review
    T.must(@review_generator = T.let(PullRequests::Copilot::CodeReviewGenerator.new(
      repo: T.must(@repo),
      pull: T.must(@pull),
      requestor: T.must(@requestor),
    ), T.nilable(PullRequests::Copilot::CodeReviewGenerator)))
  end

  private

  sig { params(message: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def requested_or_rerequested?(message)
    message[:action].to_s.in?([ReviewRequest::REQUESTED_ACTION, ReviewRequest::REREQUESTED_ACTION])
  end

  sig { params(message: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def copilot_review_request?(message)
    app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    return false if app.nil?

    subject_user_id = message.dig(:subject_user, :id)
    subject_user_id == app.bot.id
  end

  sig { params(message: String).void }
  def log(message)
    GitHub.logger.info("hydro_fulfill_copilot_review_request_job: #{message}",
      "gh.repository.id" => @repo&.name_with_display_owner,
      "gh.user.id" => @requestor&.id,
      "gh.user.login" => @requestor&.display_login,
      "gh.pull_request.id" => @pull&.id,
      "gh.pull_request.url" => @pull&.url,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id]
    )
  end

  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def with_global_lock(&block)
    return block.call unless GitHub.flipper[:ccr_hydro_job_restraint_lock].enabled?(@pull&.repository)
    restraint = GitHub::Restraint.new
    restraint.lock!(RESTRAINT_LOCK_KEY, lock_concurrency, RESTRAINT_LOCK_TTL) do
      block.call
    end
  end

  sig { returns(Integer) }
  def lock_concurrency
    if GitHub.flipper[:ccr_hydro_job_concurrency_high].enabled?
      CONCURRENCY_HIGH
    else
      CONCURRENCY_LOW
    end
  end
end
