# typed: strict
# frozen_string_literal: true

class HydroProcessCopilotReviewResponseJob < HydroMessageJob
  include GitHub::Memoizer

  CURRENT_JOBS = 1
  LOCK_TTL = T.let(5.minutes.to_i, Integer)
  queue_as :hydro_process_copilot_review_response

  sig { returns(T.nilable(PullRequests::Copilot::CodeReviewGenerator)) }
  attr_reader :review_generator

  retry_on_dirty_exit

  sig { void }
  def perform
    # Extract request_id from headers
    @request_id = T.let(
      headers[CopilotAPI::GITHUB_REQUEST_ID_HEADER],
      T.nilable(String)
    )

    log("start HydroProcessCopilotReviewResponseJob")

    @code_review_job_id = T.let(message.dig(:metadata, :job_id), T.untyped)
    @pull = T.let(PullRequest.find_by(id: message.dig(:metadata, :pull_request_id)), T.nilable(PullRequest))
    @requestor = T.let(User.find_by(id: message.dig(:metadata, :user_id)), T.nilable(User))
    return unless @pull && @requestor

    @repo = T.let(@pull.repository, T.nilable(Repository))
    return unless @repo

    @review_generator = T.let(PullRequests::Copilot::CodeReviewGenerator.new(pull: @pull, repo: @repo, requestor: @requestor, request_id: @request_id), T.nilable(PullRequests::Copilot::CodeReviewGenerator))
    return unless @review_generator

    success = message.dig(:status, :success)
    status_code = message.dig(:status, :status_code)
    if !success
      step = message.dig(:status, :step)
      msg = message.dig(:status, :message)
      if status_code == 402
        log("code review generation failed because of exceeded quota")
        review_generator&.quota_exceeded_dismiss_review
      else
        log("code review generation failed on #{step} with #{msg}")
        review_generator&.submit_failed_review
      end
      log("end HydroProcessCopilotReviewResponseJob")
      return
    end

    lock_key = "CopilotCodeReviewResponse_#{@pull.id}_#{@pull.head_sha}"
    restraint = GitHub::Restraint.new
    restraint.lock!(lock_key, CURRENT_JOBS, LOCK_TTL) do
      duplicate_comments = nil
      if FeatureFlag.vexi.enabled?(:ccr_duplicate_comment_tracking, @requestor, default: false)
        log("checking for comment duplication")
        duplication_identifier = PullRequests::Copilot::CodeReview::DuplicationIdentifier.new(response: message, pull_request: @pull)
        duplication_identifier.process!
        if FeatureFlag.vexi.enabled?(:ccr_remove_duplicate_comments, @requestor, default: false)
          duplicate_comments = duplication_identifier.results
        end
      end

      log("calling submit_review function with message contents: #{message}")
      review = @review_generator.submit_review(message, duplicate_comments:, return_with_error: false)
      log("submitted review results: #{review}")
    end

    log("end HydroProcessCopilotReviewResponseJob")
  rescue GitHub::Restraint::UnableToLock => err
    log("duplicate job detected for sha #{T.must(@pull).head_sha}")
    Failbot.report(err)
  end

  sig { params(message: String).void }
  def log(message)
    GitHub.logger.info("hydro_process_copilot_review_response_job: #{message}",
      "gh.repository.id" => @repo&.name_with_display_owner,
      "gh.user.id" => @requestor&.id,
      "gh.user.login" => @requestor&.display_login,
      "gh.pull_request.id" => @pull&.id,
      "gh.pull_request.url" => @pull&.url,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => @request_id,
      "gh.code_review.job_id" => @code_review_job_id
    )
  end

  sig { returns(PullRequests::Copilot::CodeReview::DuplicationIdentifier) }
  memoize def duplication_identifier
    PullRequests::Copilot::CodeReview::DuplicationIdentifier.new(response: message, pull_request: T.must(@pull))
  end
end
