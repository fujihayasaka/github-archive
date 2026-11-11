# typed: strict
# frozen_string_literal: true

class HydroProcessCopilotStatusUpdateJob < HydroMessageJob
  include GitHub::Memoizer

  CURRENT_JOBS = 1
  LOCK_TTL = T.let(5.minutes.to_i, Integer)
  LOCK_KEY = "CopilotCodeReviewResponse_%{pull_id}_%{pull_head_sha}"
  PENDING_REVIEW_MESSAGE = "👋 Copilot is taking longer than usual to analyze your pull request. Hold tight!"
  queue_as :hydro_process_copilot_status_update

  retry_on_dirty_exit

  sig { void }
  def perform
    log("start HydroProcessCopilotStatusUpdateJob")

    # If we don't have a pull request or repo, we can't proceed
    return unless pull && repo

    # Check if the feature flag is enabled for the repo
    unless FeatureFlag.vexi.enabled?(:copilot_code_review_post_pending_message, repo, default: false)
      # Do not attempt to post a pending review message if the flag isn't enabled for the repo
      return
    end

    # Here we use the same lock key as the review response job to prevent race conditions
    # with the finalized review (or other concurrent reviews).
    lock_key = LOCK_KEY % { pull_id: T.must(pull).id, pull_head_sha: T.must(pull).head_sha }

    restraint = GitHub::Restraint.new
    restraint.lock!(lock_key, CURRENT_JOBS, LOCK_TTL) do
      status_type = message[:status_type].presence || :UNKNOWN_STATUS_TYPE

      # Handle different status types with appropriate actions
      case status_type
      when :IN_PROGRESS
        handle_in_progress_status
      when :UNKNOWN_STATUS_TYPE, :SUCCESS, :FAILURE, :CANCELLED, :TIMEOUT, :PARTIAL_SUCCESS
        # For now, we don't do anything for these statuses.
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
  def handle_in_progress_status
    # This is a hardcoded message for now, but we can make it dynamic later,
    # including information about the pending review itself.
    add_status_comment(PENDING_REVIEW_MESSAGE)
  end

  sig { params(comment_text: String).void }
  def add_status_comment(comment_text)
    # We need to have access to Copilot bot in order to be able to post a message as the bot.
    return unless bot

    # If there isn't a pending Copilot review, don't post a comment.
    return unless pending_review

    ActiveRecord::Base.connected_to(role: :writing) do
      T.must(T.must(pull).issue).comments.create!(
        user: bot,
        body: comment_text,
      )
      log("added status comment to PR: #{comment_text}")
    end
  rescue ActiveRecord::RecordInvalid => e
    log("failed to add status comment: #{e.message}")
    Failbot.report(e, {
      "code.namespace" => self.class.name,
      "gh.pull_request.id" => pull&.id,
      "gh.comment" => comment_text
    })
  end

  sig { returns(T.nilable(Bot)) }
  memoize def bot = Apps::Privileged.integration(:copilot_pull_request_reviewer)&.bot

  sig { returns(T.nilable(ReviewRequest)) }
  memoize def pending_review = pull&.review_requests_pending&.find_by(reviewer: bot)

  sig { returns(T.nilable(Repository)) }
  memoize def repo = pull&.repository

  sig { returns(T.nilable(PullRequest)) }
  memoize def pull = PullRequest.find_by(id: message.dig(:metadata, :pull_request_id))

  sig { returns(T.nilable(String)) }
  memoize def request_id = headers[CopilotAPI::GITHUB_REQUEST_ID_HEADER]

  sig { returns(T.untyped) }
  def code_review_job_id = message.dig(:metadata, :review_id)
end
