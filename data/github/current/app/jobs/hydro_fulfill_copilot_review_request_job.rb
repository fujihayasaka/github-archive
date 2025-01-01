# typed: strict
# frozen_string_literal: true

class HydroFulfillCopilotReviewRequestJob < HydroMessageJob
  queue_as :hydro_fulfill_copilot_review_request

  retry_on_dirty_exit
  retry_on CopilotAPI::UnauthorizedError, max_retries: 1

  # Public: if message is requesting a review from Copilot, this job will
  # generate a review from Copilot.
  sig { void }
  def perform
    # Don't trigger for unrequested review requests.
    return unless requested_or_rerequested?(message)

    # Only trigger when requesting Copilot for review.
    return unless copilot_review_request?(message)

    repo = Repository.find_by(id: message.dig(:repository, :id))
    return if repo.nil?

    pull = PullRequest.find_by(id: message.dig(:pull_request, :id))
    return if pull.nil?

    requestor = User.find_by(id: message.dig(:actor, :id))
    return if requestor.nil?

    code_review_access = PullRequests::Copilot::CodeReviewAccess.new(actor: requestor, current_repository: repo)
    return unless code_review_access.can_create_review_request?

    PullRequests::Copilot::CodeReviewGenerator.new(
      repo: repo,
      pull: pull,
      requestor: requestor,
    ).generate
  rescue CopilotAPI::NotFoundError, CopilotAPI::UnauthorizedError, CopilotAPI::NetworkError => err
    Failbot.report(err)

    # For retryable errors, re-raise so the job is retried.
    # For non-retryable errors, re-raise so we get a `github.hydro_message_job.error` metric.
    raise err
  end

  private

  sig { params(message: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def requested_or_rerequested?(message)
    message[:action].to_s.in?([ReviewRequest::REQUESTED_ACTION, ReviewRequest::REREQUESTED_ACTION])
  end

  sig { params(message: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def copilot_review_request?(message)
    app = ::Apps::Internal.integration(:copilot_pull_request_reviewer)
    return false if app.nil?

    subject_user_id = message.dig(:subject_user, :id)
    subject_user_id == app.bot.id
  end
end
