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
  # Set to break-even on Pro+ at full CCR utilization per copilot#29619.
  COPILOT_MODEL_MULTIPLIER_ANNUAL = 13.0
  COPILOT_MODEL = "Code Review model"


  # Messages sent from CCRA when PR diff exceeds size limits
  TOO_MANY_FILES_MESSAGE = "Too many files in PR"
  TOO_MANY_LINES_MESSAGE = "Too many lines in PR"
  BILLING_NOT_CONFIGURED_MESSAGE = "Billing not configured"

  # Message sent from CCRA when all PR files are excluded by Copilot content
  # exclusion policy. github/copilot-code-review#962
  CONTENT_EXCLUDED_MESSAGE = "Content excluded"

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

      env_error_body = PullRequests::Copilot::CodeReviewCreator.environment_error_body_for(msg)
      if env_error_body
        log("code review generation failed because of an environment error on #{step}: #{msg}")
        review_generator.submit_failed_review(reason: PullRequests::Copilot::CodeReviewCreator::REASON_ENVIRONMENT_ERROR, error_review_body: env_error_body)
      elsif status_code == 402
        if msg == BILLING_NOT_CONFIGURED_MESSAGE
          log("code review generation failed because of billing not configured")
          review_generator.submit_failed_review(reason: PullRequests::Copilot::CodeReviewCreator::REASON_BILLING)
        else
          log("code review generation failed because of exceeded quota: #{msg}")
          review_generator.submit_failed_review(reason: PullRequests::Copilot::CodeReviewAccess::Reason.actor_has_no_quota_remaining.reason.to_s)
        end
      elsif status_code == 413
        if msg == TOO_MANY_FILES_MESSAGE
          log("code review skipped - pull request has too many files")
          review_generator.submit_failed_review(reason: PullRequests::Copilot::CodeReviewCreator::REASON_TOO_MANY_FILES)
        elsif msg == TOO_MANY_LINES_MESSAGE
          log("code review skipped - pull request has too many lines")
          review_generator.submit_failed_review(reason: PullRequests::Copilot::CodeReviewCreator::REASON_TOO_MANY_LINES)
        else
          log("code review generation failed because of payload too large: #{msg}")
          review_generator.submit_failed_review(reason: PullRequests::Copilot::CodeReviewCreator::REASON_PR_TOO_LARGE)
        end
      elsif status_code == 403 && msg == CONTENT_EXCLUDED_MESSAGE
        log("code review skipped - all files excluded by Copilot content exclusion policy")
        review_generator.submit_failed_review(reason: PullRequests::Copilot::CodeReviewCreator::REASON_CONTENT_EXCLUDED)
      else
        log("code review generation failed on #{step} with #{msg}")
        review_generator.submit_failed_review(reason: "step_failed_#{step}")
      end

      log("end HydroProcessCopilotReviewResponseJob")
      return
    end

    lock_key = "CopilotCodeReviewResponse_#{T.must(pull).id}_#{T.must(pull).head_sha}"
    restraint = GitHub::Restraint.new

    restraint.lock!(lock_key, CURRENT_JOBS, LOCK_TTL) do
      log("checking for comment duplication")
      duplication_identifier.process!
      duplicate_comments = duplication_identifier.results

      log("calling submit_review function with message contents: #{message}")
      review = review_generator.submit_review(message, duplicate_comments:, return_with_error: false)
      log("submitted review results: #{review}")

      # Gate quota emission solely on the typed Status.Step == :SKIPPED signal from
      # CCRA (hydro proto Step.SKIPPED = 11). Gating on copilot_usage / total_nano_aiu
      # field presence was tried earlier but is semantically wrong — usage-shape drift
      # or a real review that happened to bill zero AIU would silently stop quota/billing
      # telemetry. The durable source of truth for "no review happened" is the typed
      # skipped state; malformed-usage shape is a separate operational signal,
      # not a skip signal.
      is_skipped_review = message.dig(:status, :step) == :SKIPPED

      if review == :succeeded && !is_skipped_review
        # Defensive: real successful reviews should have positive total_nano_aiu.
        # If they don't, log it (with a recognizable prefix so a metric/saved search
        # can monitor cardinality). DELIBERATELY no Failbot.report here — during
        # rollout (consumer lands before producer, partial CCRA rollout, replay,
        # schema lag) every old-producer event would trigger an alert, creating
        # significant noise. Once producer rollout is verified post-deploy, we can
        # add Failbot back via a follow-up if missing usage is genuinely exceptional.
        # See github/copilot-code-review#2274.
        total_nano_aiu = message.dig(:copilot_usage, :total_nano_aiu).to_i
        unless total_nano_aiu.positive?
          log("malformed copilot_usage on successful review: total_nano_aiu=#{total_nano_aiu} (expected > 0). Emitting QuotaEvent anyway; investigate producer.")
        end

        ccr_access = PullRequests::Copilot::CodeReviewAccess.new(
          actor: T.must(requestor),
          current_repository: T.must(repo),
        )
        if ccr_access.should_bill_to_organization?
          copilot_access_type = nil
          org = T.must(repo).organization
          copilot_tracking_id = T.must(org).analytics_tracking_id
          quota_request_type = :ORG_INITIATED
          is_token_based_billing = Copilot::Organization.new(T.must(org)).use_token_based_billing?
        else
          copilot_user = Copilot::User.new(T.must(requestor))
          copilot_access_type = copilot_user.access_type
          copilot_tracking_id = T.must(requestor).analytics_tracking_id
          quota_request_type = :USER_INITIATED
          is_token_based_billing = copilot_user.use_token_based_billing?
        end

        model_multiplier = if is_token_based_billing && Copilot::Authorization::AccessLoader::YEARLY_ACCESS_TYPES.include?(copilot_access_type)
          COPILOT_MODEL_MULTIPLIER_ANNUAL
        else
          COPILOT_MODEL_MULTIPLIER
        end

        service_request_id = SecureRandom.uuid

        # Emit quota event; this is the event that will charge the user.
        quota_event_message = {
          integration_id: COPILOT_INTEGRATION_ID,
          interaction_type: COPILOT_INTERACTION_TYPE,
          is_premium: true,
          model_multiplier:,
          copilot_tracking_id:,
          copilot_access_type:,
          feature: QUOTA_EVENT_FEATURE,
          github_copilot_units: QUOTA_EVENT_UNITS,
          quota_source: :CCR,
          quota_request_type:,
          github_request_id: request_id_from_metadata,
          model: COPILOT_MODEL,
          model_name: COPILOT_MODEL,
          is_token_based_billing:,
          repo_id: T.must(repo).id,
          service_request_id:,
          **token_based_billing_fields,
        }

        quota_event_message[:interaction_id] = interaction_id if interaction_id

        Hydro::PublishRetrier.publish(quota_event_message, schema: "copilot.v0.QuotaEvent", publisher: GitHub.hydro_copilot_publisher)
        log("emitted QuotaEvent with service_request_id=#{service_request_id}")
      elsif review == :succeeded
        log("skipping quota event: status.step == :SKIPPED")
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
      "gh.repository.id" => repo&.id,
      "gh.repository.nwo" => repo&.name_with_display_owner,
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

  sig { returns(T.nilable(String)) }
  def interaction_id
    message.dig(:interaction_id)
  end

  # Extracts copilot_usage fields from the response message for inclusion in the QuotaEvent.
  # The token_details arrive in BillableToken format from the agent and are passed through as-is.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def token_based_billing_fields
    copilot_usage = message.dig(:copilot_usage)
    return {} unless copilot_usage

    fields = T.let({}, T::Hash[Symbol, T.untyped])

    total_nano_aiu = copilot_usage[:total_nano_aiu]
    if total_nano_aiu && total_nano_aiu > 0
      fields[:aiu_quantity_nano] = total_nano_aiu
    end

    token_details = copilot_usage[:token_details]
    if token_details.is_a?(Array) && token_details.any?
      fields[:billable_token] = token_details
    end

    fields
  end
end
