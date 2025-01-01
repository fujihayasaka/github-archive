# typed: strict
# frozen_string_literal: true

class HydroFulfillCopilotReviewRequestJob < HydroMessageJob
  queue_as :hydro_fulfill_copilot_review_request

  retry_on_dirty_exit
  retry_on CopilotAPI::UnauthorizedError, max_retries: 1 do |job, _error|
    job.submit_failed_review_error
  end


  sig { returns(T.nilable(PullRequests::Copilot::CodeReviewGenerator)) }
  attr_reader :review_generator

  sig { params(protobuf: T.untyped, headers: T.untyped, schema: T.untyped, timestamp: T.untyped, timestamp_nano: T.untyped, message: T.untyped, queue: T.untyped).void }
  def initialize(protobuf:, headers:, schema:, timestamp:, timestamp_nano:, message:, queue:)
    super

    @review_generator = nil
  end

  # Public: if message is requesting a review from Copilot, this job will
  # generate a review from Copilot.
  sig { void }
  def perform
    # Don't trigger for unrequested review requests.
    return unless requested_or_rerequested?(message)

    # Only trigger when requesting Copilot for review.
    return unless copilot_review_request?(message)

    repo = T.let(Repository.find_by(id: message.dig(:repository, :id)), T.nilable(Repository))
    return if repo.nil?

    pull = T.let(PullRequest.find_by(id: message.dig(:pull_request, :id)), T.nilable(PullRequest))
    return if pull.nil?

    requestor = T.let(User.find_by(id: message.dig(:actor, :id)), T.nilable(User))
    return if requestor.nil?

    code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: requestor, current_repository: repo)
    return unless code_review_access.can_create_review_request?

    @review_generator ||= T.let(PullRequests::Copilot::CodeReviewGenerator.new(
      repo: repo,
      pull: pull,
      requestor: requestor,
    ), T.nilable(PullRequests::Copilot::CodeReviewGenerator))

    T.must(review_generator).generate

  rescue CopilotAPI::NotFoundError, CopilotAPI::NetworkError => err
    Failbot.report(err)

    # For retryable errors, re-raise so the job is retried.
    # For non-retryable errors, re-raise so we get a `github.hydro_message_job.error` metric.
    raise err
  end

  sig { void }
  def submit_failed_review_error
    review_generator&.submit_failed_review
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
end
