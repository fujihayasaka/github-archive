# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

class HydroFulfillCopilotReviewRequestJob < HydroMessageJob
  MAX_RESTRAINT_RETRIES = 5
  RESTRAINT_LOCK_KEY = T.let("hydro_fulfill_copilot_review_request_job".freeze, String)
  RESTRAINT_LOCK_TTL = T.let(5.minutes.to_i, Integer)
  RESTRAINT_LOCK_CONCURRENCY = 250

  queue_as :hydro_fulfill_copilot_review_request

  retry_on_dirty_exit
  retry_on CopilotAPI::UnauthorizedError, CopilotAPI::NetworkError, max_retries: 1 do |job, error|
    GitHub.dogstats.increment("copilot.code_review.persistence.retry_failed")
    Failbot.report(error)

    job.log("retry failed: #{error}")
    job.submit_failed_review_error(reason: "persistence_retry_failed")
  end

  retry_on GitHub::Restraint::UnableToLock, delay: :polynomially_longer, max_retries: MAX_RESTRAINT_RETRIES do |job, error|
    GitHub.dogstats.increment("copilot.code_review.retries_exhausted")
    Failbot.report(error)

    job.log("retries exhausted: #{error}")
    job.submit_failed_review_error(reason: "retries_exhausted")
  end

  retry_on ActiveRecord::ConnectionFailed, ActiveRecord::ConnectionNotEstablished, delay: :polynomially_longer, max_retries: 3 do |job, error|
    GitHub.dogstats.increment("copilot.code_review.db_retries_exhausted")
    Failbot.report(error)

    job.log("db retries exhausted: #{error}")
    job.submit_failed_review_error(reason: "db_retries_exhausted")
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

    if FeatureFlag.vexi.enabled?(:repos_by_id_jobs, default: false)
      @repo = T.let(T.cast(Repositories.domain.by_id(message.dig(:repository, :id)), T.nilable(Repository)), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      @repo = T.let(Repository.find_by(id: message.dig(:repository, :id)), T.nilable(Repository))
    end
    @pull = T.let(PullRequest.find_by(id: message.dig(:pull_request, :id)), T.nilable(PullRequest))
    @requestor = T.let(User.find_by(id: message.dig(:actor, :id)), T.nilable(User))
    @request_id = T.let(
      # Pull the request_id from headers or message context
      headers[CopilotAPI::GITHUB_REQUEST_ID_HEADER] || message.dig(:request_context, :request_id),
      T.nilable(String)
    )
    @bot_requestor_allowed = T.let(bot_requestor_allowed?, T.nilable(T::Boolean))

    perform_review_request
  end

  sig { params(reason: String).void }
  def submit_failed_review_error(reason:)
    review_generator.submit_failed_review(reason: reason)
  rescue StandardError => error
    log("failed to submit review error: #{error.message}")
    Failbot.report(error)
  end

  sig { void }
  def quota_exceeded_dismiss_review
    review_generator.quota_exceeded_dismiss_review
  end

  sig { void }
  def dismiss_review_request_for_invalid_requestor
    return unless @pull

    app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    return unless app

    review_request = @pull.direct_review_request_for(app.bot)
    return unless review_request

    ActiveRecord::Base.connected_to(role: :writing) do
      review_request.dismiss
      review_request.save
    end

    log("dismissed review request for invalid requestor")
  end

  sig { returns(PullRequests::Copilot::CodeReviewGenerator) }
  def review_generator
    return T.must(@review_generator) if defined?(@review_generator)
    # we have to assume that @pull is not nil here so that we can actually submit a failed review

    T.must(@review_generator = T.let(PullRequests::Copilot::CodeReviewGenerator.new(
      repo: T.must(@repo),
      pull: T.must(@pull),
      requestor: T.must(@requestor),
      allow_bot_requestor: !!@bot_requestor_allowed,
      request_id: @request_id
    ), T.nilable(PullRequests::Copilot::CodeReviewGenerator)))
  end

  sig { params(message: String).void }
  def log(message)
    GitHub.logger.info("hydro_fulfill_copilot_review_request_job: #{message}",
      "gh.repository.id" => @repo&.id,
      "gh.repository.nwo" => @repo&.name_with_display_owner,
      "gh.user.id" => @requestor&.id,
      "gh.user.login" => @requestor&.display_login,
      "gh.pull_request.id" => @pull&.id,
      "gh.pull_request.url" => @pull&.url,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => @request_id
    )
  end

  private

  sig { void }
  def perform_review_request
    # Don't trigger for unrequested review requests.
    return unless requested_or_rerequested?(message)

    # Only trigger when requesting Copilot for review.
    unless copilot_review_request?(message)
      return
    end

    GitHub.dogstats.increment("copilot.code_review.hydro_fulfill_job", tags: ["status:requested"])

    unless @requestor && (@requestor.user? || @bot_requestor_allowed)
      GitHub.dogstats.increment("copilot.code_review.hydro_fulfill_job", tags: ["status:failed", "reason:requestor_not_a_user"])
      log("requestor is nil or not a user, dismissing review request")
      dismiss_review_request_for_invalid_requestor
      return
    end

    if @requestor.bot? && @bot_requestor_allowed
      GitHub.dogstats.increment("copilot.code_review.hydro_fulfill_job", tags: ["status:bot_requestor_allowed"])
      log("bot requestor allowed via direct org billing")
    end

    code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: @requestor, current_repository: @repo)
    access_reason = code_review_access.can_create_review_request_reason
    unless access_reason.access
      reason = access_reason.reason
      GitHub.dogstats.increment("copilot.code_review.hydro_fulfill_job", tags: ["status:failed", "reason:#{reason}"])
      log("actor cannot create review request")
      submit_failed_review_error(reason: "#{reason}")
      return
    end
    log("actor has proper access")

    if FeatureFlag.vexi.enabled?(:copilot_code_review_disabled, @requestor, default: false)
      submit_failed_review_error(reason: PullRequests::Copilot::CodeReviewCreator::REASON_COPILOT_UNAVAILABLE)
      return
    end

    with_global_lock do
      log("start CodeReviewGenerator")
      unless review_generator.generate
        log("review generation failed")
        GitHub.dogstats.increment("copilot.code_review.hydro_fulfill_job", tags: ["status:failed", "reason:review_generation_failed"])
        submit_failed_review_error(reason: "review_generation_failed")
      end
      log("finish CodeReviewGenerator")
    end

  # Re-raise retryable errors so retry_on can handle them. Keep in sync with
  # retry_on declarations, otherwise rescue StandardError will swallow them.
  rescue GitHub::Restraint::UnableToLock, CopilotAPI::UnauthorizedError, CopilotAPI::NetworkError,
         ActiveRecord::ConnectionFailed, ActiveRecord::ConnectionNotEstablished
    raise
  rescue CopilotAPI::QuotaExceededError => err
    GitHub.dogstats.increment("copilot.code_review.quota_exceeded")
    quota_exceeded_dismiss_review
  rescue StandardError => err
    Failbot.report(err)

    # Any errors we get that we do not retry, we need to clean up and return a review comment saying that we failed.
    log("unexpected error: #{err.message}")
    submit_failed_review_error(reason: "unexpected_error")
  end

  sig { params(message: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def requested_or_rerequested?(message)
    message[:action].to_s.in?([ReviewRequest::REQUESTED_ACTION, ReviewRequest::REREQUESTED_ACTION])
  end

  sig { params(message: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def copilot_review_request?(message)
    log("getting copilot_pull_request_reviewer app info")
    app = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)
    if app.nil?
      log("copilot_pull_request_reviewer app not found")
      return false
    end

    subject_user_id = message.dig(:subject_user, :id)
    log("subject_user_id: #{subject_user_id}, app bot id: #{app.bot.id}")
    subject_user_id == app.bot.id
  end

  sig { returns(T::Boolean) }
  def bot_requestor_allowed?
    return false unless @requestor&.bot?

    organization = @repo&.organization
    return false unless organization

    code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: @requestor, current_repository: @repo)
    code_review_access.should_bill_to_organization?
  end

  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def with_global_lock(&block)
    restraint = GitHub::Restraint.new
    restraint.lock!(RESTRAINT_LOCK_KEY, RESTRAINT_LOCK_CONCURRENCY, RESTRAINT_LOCK_TTL) do
      block.call
    end
  end
end
