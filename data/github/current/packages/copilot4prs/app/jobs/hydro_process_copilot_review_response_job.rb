# typed: strict
# frozen_string_literal: true

class HydroProcessCopilotReviewResponseJob < HydroMessageJob
  include GitHub::Memoizer

  # Values used to publish QuotaEvent
  QUOTA_EVENT_FEATURE = "chat"
  QUOTA_EVENT_UNITS = 1
  COPILOT_INTEGRATION_ID = "copilot-pr-reviews"
  COPILOT_INTERACTION_TYPE = "code-review"
  COPILOT_MODEL_MULTIPLIER = 1.0
  COPILOT_MODEL = "Code Review model"

  CURRENT_JOBS = 1
  LOCK_TTL = T.let(5.minutes.to_i, Integer)
  queue_as :hydro_process_copilot_review_response

  retry_on_dirty_exit

  sig { void }
  def perform
    log("start HydroProcessCopilotReviewResponseJob")

    return unless pull && requestor && repo

    success = message.dig(:status, :success)
    status_code = message.dig(:status, :status_code)
    if !success
      step = message.dig(:status, :step)
      msg = message.dig(:status, :message)
      if status_code == 402
        log("code review generation failed because of exceeded quota")
        review_generator.quota_exceeded_dismiss_review
      else
        log("code review generation failed on #{step} with #{msg}")
        review_generator.submit_failed_review
      end
      log("end HydroProcessCopilotReviewResponseJob")
      return
    end

    lock_key = "CopilotCodeReviewResponse_#{T.must(pull).id}_#{T.must(pull).head_sha}"
    restraint = GitHub::Restraint.new

    restraint.lock!(lock_key, CURRENT_JOBS, LOCK_TTL) do
      duplicate_comments = if FeatureFlag.vexi.enabled?(:ccr_duplicate_comment_tracking, requestor, default: false)
        log("checking for comment duplication")
        duplication_identifier.process!

        if FeatureFlag.vexi.enabled?(:ccr_remove_duplicate_comments, T.must(requestor), default: false)
          duplication_identifier.results
        end
      end

      log("calling submit_review function with message contents: #{message}")
      review = review_generator.submit_review(message, duplicate_comments:, return_with_error: false)
      log("submitted review results: #{review}")

      if review == :succeeded && T.must(requestor).feature_flag_enabled?(:copilot_code_reviews_use_agent_initiator, default: false)
        ccr_access = PullRequests::Copilot::CodeReviewAccess.new(
          actor: T.must(requestor),
          current_repository: T.must(repo),
        )
        if ccr_access.should_bill_to_organization?
          copilot_access_type = nil
          org = T.must(repo).organization
          copilot_tracking_id = T.must(org).analytics_tracking_id
          quota_request_type = :ORG_INITIATED
        else
          copilot_user = Copilot::User.new(T.must(requestor))
          copilot_access_type = copilot_user.access_type
          copilot_tracking_id = T.must(requestor).analytics_tracking_id
          quota_request_type = :USER_INITIATED
        end

        # Emit quota event; this is the event that will charge the user.
        quota_event_message = {
          integration_id: COPILOT_INTEGRATION_ID,
          interaction_type: COPILOT_INTERACTION_TYPE,
          is_premium: true,
          model_multiplier: COPILOT_MODEL_MULTIPLIER,
          copilot_tracking_id:,
          copilot_access_type:,
          feature: QUOTA_EVENT_FEATURE,
          github_copilot_units: QUOTA_EVENT_UNITS,
          quota_source: :CCR,
          quota_request_type:,
          github_request_id: request_id_from_metadata,
          model: COPILOT_MODEL,
          model_name: COPILOT_MODEL,
        }

        Hydro::PublishRetrier.publish(quota_event_message, schema: "copilot.v0.QuotaEvent", publisher: GitHub.hydro_copilot_publisher)
      end
    end

    log("end HydroProcessCopilotReviewResponseJob")
  rescue GitHub::Restraint::UnableToLock => err
    log("duplicate job detected for sha #{T.must(pull).head_sha}")
    Failbot.report(err)
  end

  private

  sig { params(message: String).void }
  def log(message)
    GitHub.logger.info("hydro_process_copilot_review_response_job: #{message}",
      "gh.repository.id" => repo&.name_with_display_owner,
      "gh.user.id" => requestor&.id,
      "gh.user.login" => requestor&.display_login,
      "gh.pull_request.id" => pull&.id,
      "gh.pull_request.url" => pull&.url,
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => request_id,
      "gh.code_review.job_id" => code_review_job_id,
    )
  end

  sig { returns(PullRequests::Copilot::CodeReviewGenerator) }
  memoize def review_generator
    PullRequests::Copilot::CodeReviewGenerator.new(
      pull: T.must(pull),
      repo: T.must(repo),
      requestor: T.must(requestor),
      request_id:,
    )
  end

  sig { returns(PullRequests::Copilot::CodeReview::DuplicationIdentifier) }
  memoize def duplication_identifier
    PullRequests::Copilot::CodeReview::DuplicationIdentifier.new(response: message, pull_request: T.must(pull))
  end

  sig { returns(T.nilable(Repository)) }
  memoize def repo
    T.must(pull).repository
  end

  sig { returns(T.nilable(User)) }
  memoize def requestor
    User.find_by(id: message.dig(:metadata, :user_id))
  end

  sig { returns(T.nilable(PullRequest)) }
  memoize def pull
    PullRequest.find_by(id: message.dig(:metadata, :pull_request_id))
  end

  sig { returns(T.nilable(String)) }
  memoize def request_id
    headers[CopilotAPI::GITHUB_REQUEST_ID_HEADER]
  end

  sig { returns(T.nilable(String)) }
  memoize def request_id_from_metadata
    message.dig(:metadata, :request_id)
  end

  sig { returns(T.untyped) }
  def code_review_job_id
    message.dig(:metadata, :job_id)
  end
end
