# typed: true
# frozen_string_literal: true

# Helper module for building StandardEvent messages for the analytics-pipelines
# dual-publishing migration. See https://github.com/github/copilot-code-review/issues/1678
# and https://github.com/github/copilot-code-review/issues/1679.
module CopilotReviewsStandardEvent
  EVENT_VERSION = "0.0.1"
  OWNING_SERVICE = "copilot-code-review"
  GITHUB_PULL_REQUEST_ID = "github_pull_request_id"
  COPILOT_TRACKING_ID = "copilot_tracking_id"
  TOPIC = "copilot.reviews.analytics_pipelines.v0.StandardEvent"
  SCHEMA = "hydro.schemas.analytics_pipelines.v0.StandardEvent"

  module_function

  # Returns true when emission should actually publish. Production-only
  # (no GHES, no Proxima).
  def dual_publish_enabled?
    return false if GitHub.enterprise?  # Excludes GHES
    return false if GitHub.multi_tenant_enterprise?  # Excludes Proxima

    true
  end

  # Builds a StandardEvent message hash matching
  # hydro.schemas.analytics_pipelines.v0.StandardEvent. `metadata` values
  # must be coerced to strings; nils are dropped. Callers are responsible
  # for resolving `primary_assignment_context` via the appropriate helper
  # for the source event (see decision_run_for / assignment_context_for_review).
  def build(event_type:, deduplication_id:, pull_request_id:, tracking_id:, primary_assignment_context:, comment_identifier: nil, request_id: nil, metadata: {}, conditions: {}, measurements: {})
    {
      event_type: event_type,
      owning_service: OWNING_SERVICE,
      occurred_at: Time.now.utc,
      deduplication_id: deduplication_id,
      event_version: EVENT_VERSION,
      # The CCRA-generated comment identifier (a GUID) correlates this event
      # with the originating CCR comment across services; nil for events that
      # aren't scoped to a single comment.
      activity_correlation_id: comment_identifier.presence,
      # The CCR review request_id groups every event for one review; it joins
      # with the CCRA-emitted StandardEvents that carry the same value.
      session_id: request_id.presence,
      primary_assignment_context: primary_assignment_context,
      primary_entity_id: pull_request_id.to_s,
      primary_entity_id_type: GITHUB_PULL_REQUEST_ID,
      secondary_entity_id: tracking_id.presence,
      secondary_entity_id_type: tracking_id.present? ? COPILOT_TRACKING_ID : nil,
      measurements: measurements,
      conditions: conditions.merge("from_dotcom" => true),
      metadata: metadata.compact.transform_values { |v| serialize_metadata_value(v) },
    }
  end

  # Resolves the CCR decision run for an event tagged by a PRRC `comment_id`
  # on a known `pull_request_id`. Callers derive specific fields
  # (`experiment_assignment_context`, `response_request_id`) from the
  # returned run.
  #
  # `pull_request_id` constrains the lookup so that non-PRRC `comment_id`s
  # (e.g. CCR finding IDs from CodeReviewFindingsController, or
  # PullRequestReview.ids from the REVIEW_SUMMARY feedback widget) cannot
  # accidentally collide with an unrelated PRRC and publish a StandardEvent
  # attributed to the wrong CCR experiment cohort.
  #
  # Returns nil for: blank/non-integer ids; PRRC not on the given PR;
  # comment isn't on a CCR-created review; unexpected DB error (logged
  # via dogstats). Callers MUST NOT dual-publish on nil.
  def decision_run_for(comment_id, pull_request_id)
    parsed_comment_id = Kernel.Integer(comment_id.to_s, exception: false)
    return nil if parsed_comment_id.nil?

    parsed_pull_request_id = Kernel.Integer(pull_request_id.to_s, exception: false)
    return nil if parsed_pull_request_id.nil?

    pull_request_review_id = PullRequestReviewComment
      .where(id: parsed_comment_id, pull_request_id: parsed_pull_request_id)
      .pick(:pull_request_review_id)

    return nil unless pull_request_review_id

    PullRequests::Copilot::CcrDecisionRunStore.run_for_pull_request_review_id(
      pull_request_review_id: pull_request_review_id,
    )
  rescue StandardError => e
    GitHub.dogstats.increment(
      "copilot.code_review.standard_event.dual_publish_lookup_error",
      tags: ["exception:#{e.class.name}"],
    )
    nil
  end

  # Resolves the CcrDecisionRun for an event that already carries a
  # `pull_request_review_id` (e.g. CcrDecisionAssessment, RecallAnalysis).
  # Skips the comment lookup since the review id is known directly.
  #
  # Returns the run, or nil for: blank/non-integer pull_request_review_id;
  # no CcrDecisionRun recorded for this review; unexpected DB error (logged
  # via dogstats). Callers MUST treat nil as "do not dual-publish".
  def decision_run_for_review(pull_request_review_id)
    parsed_id = Kernel.Integer(pull_request_review_id.to_s, exception: false)
    return nil if parsed_id.nil?

    PullRequests::Copilot::CcrDecisionRunStore.run_for_pull_request_review_id(
      pull_request_review_id: parsed_id,
    )
  rescue StandardError => e
    GitHub.dogstats.increment(
      "copilot.code_review.standard_event.dual_publish_lookup_error",
      tags: ["exception:#{e.class.name}"],
    )
    nil
  end

  # Resolves the CCR experiment assignment context for an event that
  # already carries a `pull_request_review_id` (e.g. CcrDecisionAssessment).
  # Skips the comment lookup since the review id is known directly.
  #
  # Returns:
  #   String -> a non-empty CCR experiment assignment context. Caller
  #             SHOULD dual-publish, using this as `primary_assignment_context`.
  #   nil    -> no usable context resolved. Caller MUST NOT dual-publish.
  #             Covers: blank/non-integer pull_request_review_id; no
  #             CcrDecisionRun recorded for this review (data inconsistency
  #             — the upstream pipeline that emits the event is what writes
  #             the run); CcrDecisionRun exists but has nil/empty
  #             assignment context (the upstream agent dropped context on
  #             a fallback/timeout path); unexpected DB error (logged via
  #             dogstats).
  #
  # Mirrors `assignment_context_for`'s nil/String contract so the
  # CcrDecisionAssessment subscriber can gate dual-publish identically to
  # Feedback and CommentAnalysis. The legacy `copilot.reviews.v0.*` topics
  # still receive every event for any non-experimental consumers.
  def assignment_context_for_review(pull_request_review_id)
    decision_run_for_review(pull_request_review_id)&.experiment_assignment_context.presence
  end

  # Normalizes a metadata value to a stable string form. Time/DateTime
  # values are emitted as ISO8601 in UTC so downstream analytics parsing
  # is consistent regardless of the originating timezone or formatting.
  def serialize_metadata_value(value)
    case value
    when Time, DateTime
      value.utc.iso8601
    when Date
      value.iso8601
    else
      value.to_s
    end
  end
end

# These are GlobalInstrumenter subscriptions that emit Hydro events related to GitHub Copilot Reviews v0.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("copilot.reviews.v0.Feedback") do |payload|
    access_type = payload[:copilot_access_type]
    access_type = :UNKNOWN if [:NO_ACCESS, :FEATURE_FLAG_BLOCKED].include?(access_type)
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        comment_id: payload[:comment_id],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
        custom_instructions_included: payload[:custom_instructions_included],
        feedback_target: payload[:feedback_target],
      },
      type: payload[:type],
      copilot_access_type: access_type,
    }

    publish(message, schema: "copilot.reviews.v0.Feedback")

    if CopilotReviewsStandardEvent.dual_publish_enabled?
      decision_run = CopilotReviewsStandardEvent.decision_run_for(payload[:comment_id], payload[:pull_request_id])
      assignment_context = decision_run&.experiment_assignment_context.presence
      if !assignment_context.nil?
        standard_event = CopilotReviewsStandardEvent.build(
          event_type: "copilot_code_review_feedback",
          deduplication_id: "#{payload[:request_id]}:#{payload[:comment_id]}:#{payload[:type]}",
          pull_request_id: payload[:pull_request_id],
          tracking_id: payload[:analytics_tracking_id],
          # CCRA-generated comment identifier (GUID) — correlates this event
          # with the originating CCR comment via `activity_correlation_id`.
          comment_identifier: payload[:comment_identifier],
          # CCR review request_id — populates `session_id`, aligning this event
          # with the CCRA-emitted `copilot.reviews.v0.ReviewComment` and the
          # PR-owned StandardEvents (which also use `response_request_id`).
          # Without this, the field would carry the per-feedback-click Rails
          # request_id, which fans out N:1 with the comment.
          request_id: decision_run.response_request_id,
          primary_assignment_context: assignment_context,
          metadata: {
            "request_id" => payload[:request_id],
            "organization_id" => payload[:organization_id],
            "repository_id" => payload[:repository_id],
            "comment_id" => payload[:comment_id],
            # CCRA-generated comment identifier (mirrors `comment_identifier`
            # on `copilot.reviews.v0.ReviewComment`). Lets consumers
            # aggregate by a single comment key across CCRA and dotcom
            # events without an additional join. Nil for human comments
            # and pre-AutomatedReviewComment rows (dropped via .compact).
            "comment_identifier" => payload[:comment_identifier],
            "feedback_type" => payload[:type],
            "feedback_target" => payload[:feedback_target],
            "copilot_access_type" => access_type,
          },
          conditions: {
            "custom_instructions_included" => !!payload[:custom_instructions_included],
          },
        )
        publish(
          standard_event,
          schema: CopilotReviewsStandardEvent::SCHEMA,
          topic: CopilotReviewsStandardEvent::TOPIC,
          publisher: GitHub.hydro_copilot_publisher,
        )
      end
    end
  end

  subscribe("copilot.reviews.v0.RestrictedFeedback") do |payload|
    access_type = payload[:copilot_access_type]
    access_type = :UNKNOWN if [:NO_ACCESS, :FEATURE_FLAG_BLOCKED].include?(access_type)
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        comment_id: payload[:comment_id],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
        custom_instructions_included: payload[:custom_instructions_included],
        feedback_target: payload[:feedback_target],
      },
      text_response: payload[:text_response],
      feedback_choice: payload[:feedback_choice],
      copilot_access_type: access_type,
    }

    publish(message, schema: "copilot.reviews.v0.RestrictedFeedback")
  end

  subscribe("copilot.reviews.v0.ReviewCommentPersistenceMapping") do |payload|
    message = {
      generated_comment_uuid: payload[:generated_comment_uuid],
      comment_id: payload[:comment_id],
      comment_creation_status: payload[:comment_creation_status],
      pull_request_id: payload[:pull_request_id],
      thread_id: payload[:thread_id]
    }

    publish(message, schema: "copilot.reviews.v0.ReviewCommentPersistenceMapping")
  end

  subscribe("copilot.reviews.v0.RestrictedReviewCommentPersistenceMapping") do |payload|
    message = {
      generated_comment_uuid: payload[:generated_comment_uuid],
      comment_id: payload[:comment_id],
      comment_creation_status: payload[:comment_creation_status],
      pull_request_id: payload[:pull_request_id],
      thread_id: payload[:thread_id]
    }

    publish(message, schema: "copilot.reviews.v0.RestrictedReviewCommentPersistenceMapping")
  end

  subscribe("copilot_code_review_agent.v0.CopilotCodeReviewThreadReplyRequested") do |payload|
    actor = User.find_by(id: payload[:actor_id])
    pull_request = PullRequest.find_by(id: payload[:pull_request_id])
    pull_request_review = PullRequestReview.find_by(id: payload[:pull_request_review_id])
    pull_request_review_comment = PullRequestReviewComment.find_by(id: payload[:pull_request_review_comment_id])
    pull_request_review_thread = PullRequestReviewThread.find_by(id: payload[:pull_request_review_thread_id])
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_config, default: false)
      Repositories.domain.by_id(payload[:repository_id])
    else
      Repository.find_by(id: payload[:repository_id])
    end

    message = {
      actor: serializer.user(actor),
      pull_request: serializer.pull_request(pull_request),
      pull_request_review: serializer.pull_request_review(pull_request_review),
      pull_request_review_comment: serializer.pull_request_review_comment(pull_request_review_comment),
      pull_request_review_thread: serializer.pull_request_review_thread(pull_request_review_thread),
      repository: serializer.repository(repository),
    }

    publish(message, schema: "copilot_code_review_agent.v0.CopilotCodeReviewThreadReplyRequested")
  end

  subscribe("copilot.reviews.v0.CommentAnalysis") do |payload|
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        comment_id: payload[:comment_id],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
      },
      comment_source: payload[:comment_source],
      llm_judgment: payload[:llm_judgment],
      llm_reasoning: payload[:llm_reasoning],
      llm_error: payload[:llm_error],
      review_id: payload[:review_id],
    }
    publish(message, schema: "copilot.reviews.v0.CommentAnalysis")

    if CopilotReviewsStandardEvent.dual_publish_enabled?
      decision_run = CopilotReviewsStandardEvent.decision_run_for(payload[:comment_id], payload[:pull_request_id])
      assignment_context = decision_run&.experiment_assignment_context.presence
      if !assignment_context.nil?
        standard_event = CopilotReviewsStandardEvent.build(
          event_type: "copilot_code_review_comment_analysis",
          deduplication_id: "#{payload[:request_id]}:#{payload[:comment_id]}",
          pull_request_id: payload[:pull_request_id],
          tracking_id: payload[:analytics_tracking_id],
          # CCRA-generated comment identifier (GUID) — correlates this event
          # with the originating CCR comment via `activity_correlation_id`.
          comment_identifier: payload[:comment_identifier],
          # CCR review request_id — populates `session_id`, aligning this event
          # with the CCRA-emitted `copilot.reviews.v0.ReviewComment` and the
          # PR-owned StandardEvents. Without this, the field would carry the
          # per-analyzer-run Rails request_id (or a SecureRandom fallback),
          # which fans out N:1 with the comment.
          request_id: decision_run.response_request_id,
          primary_assignment_context: assignment_context,
          metadata: {
            "request_id" => payload[:request_id],
            "organization_id" => payload[:organization_id],
            "repository_id" => payload[:repository_id],
            "comment_id" => payload[:comment_id],
            # CCRA-generated comment identifier (mirrors `comment_identifier`
            # on `copilot.reviews.v0.ReviewComment`). Lets consumers
            # aggregate by a single comment key across CCRA and dotcom
            # events without an additional join. Nil for human comments
            # and pre-AutomatedReviewComment rows (dropped via .compact).
            "comment_identifier" => payload[:comment_identifier],
            "comment_source" => payload[:comment_source],
            "llm_judgment" => payload[:llm_judgment],
            "llm_reasoning" => payload[:llm_reasoning],
            "llm_error" => payload[:llm_error],
          },
        )
        publish(
          standard_event,
          schema: CopilotReviewsStandardEvent::SCHEMA,
          topic: CopilotReviewsStandardEvent::TOPIC,
          publisher: GitHub.hydro_copilot_publisher,
        )
      end
    end
  end

  subscribe("copilot.reviews.v0.PostApprovalAssessment") do |payload|
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
        comment_id: payload[:comment_id],
      },
      approval_review_id: payload[:approval_review_id],
      post_approval_commit_count: payload[:post_approval_commit_count],
      post_approval_comment_count: payload[:post_approval_comment_count],
      llm_judgment: payload[:llm_judgment],
      llm_reasoning: payload[:llm_reasoning],
      llm_error: payload[:llm_error],
      substantial_commit_shas: Array(payload[:substantial_commit_shas]),
    }

    publish(message, schema: "copilot.reviews.v0.PostApprovalAssessment")
  end

  subscribe("copilot.reviews.v0.CcrDecisionAssessment") do |payload|
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
        comment_id: payload[:comment_id],
      },
      pull_request_review_id: payload[:pull_request_review_id],
      response_request_id: payload[:response_request_id],
      decision_submitted_at: payload[:decision_submitted_at],
      decision_head_sha: payload[:decision_head_sha],
      approval_readiness_code: payload[:approval_readiness_code],
      review_submission_event: payload[:review_submission_event],
      post_decision_commit_count: payload[:post_decision_commit_count],
      post_decision_comment_count: payload[:post_decision_comment_count],
      post_decision_human_changes_requested_count: payload[:post_decision_human_changes_requested_count],
      llm_judgment: payload[:llm_judgment],
      llm_reasoning: payload[:llm_reasoning],
      llm_error: payload[:llm_error],
      substantial_commit_shas: Array(payload[:substantial_commit_shas]),
      analysis_status: payload[:analysis_status],
      llm_model: payload[:llm_model],
      prompt_version: payload[:prompt_version],
    }.compact

    publish(message, schema: "copilot.reviews.v0.CcrDecisionAssessment")

    if CopilotReviewsStandardEvent.dual_publish_enabled?
      # CcrDecisionAssessment carries the review id directly, so we look
      # up the assignment context that was persisted at decision time
      # rather than walking from a comment.
      assignment_context = CopilotReviewsStandardEvent.assignment_context_for_review(payload[:pull_request_review_id])
      if !assignment_context.nil?
        substantial_commit_shas = Array(payload[:substantial_commit_shas])
        standard_event = CopilotReviewsStandardEvent.build(
          event_type: "copilot_code_review_post_decision_assessment",
          deduplication_id: "#{payload[:request_id]}:#{payload[:pull_request_review_id]}",
          pull_request_id: payload[:pull_request_id],
          tracking_id: payload[:analytics_tracking_id],
          # Tie back to the original CCR review so downstream pipelines can
          # join with code_review_response on response_request_id.
          request_id: payload[:response_request_id],
          primary_assignment_context: assignment_context,
          metadata: {
            "request_id" => payload[:request_id],
            "response_request_id" => payload[:response_request_id],
            "organization_id" => payload[:organization_id],
            "repository_id" => payload[:repository_id],
            "comment_id" => payload[:comment_id],
            "pull_request_review_id" => payload[:pull_request_review_id],
            "decision_submitted_at" => payload[:decision_submitted_at],
            "decision_head_sha" => payload[:decision_head_sha],
            "approval_readiness_code" => payload[:approval_readiness_code],
            "review_submission_event" => payload[:review_submission_event],
            "llm_judgment" => payload[:llm_judgment],
            "llm_reasoning" => payload[:llm_reasoning],
            "llm_error" => payload[:llm_error],
            "analysis_status" => payload[:analysis_status],
            "llm_model" => payload[:llm_model],
            "prompt_version" => payload[:prompt_version],
            "substantial_commit_shas" => substantial_commit_shas.join(","),
          },
          measurements: {
            "post_decision_commit_count" => payload[:post_decision_commit_count].to_f,
            "post_decision_comment_count" => payload[:post_decision_comment_count].to_f,
            "post_decision_human_changes_requested_count" => payload[:post_decision_human_changes_requested_count].to_f,
            "substantial_commit_count" => substantial_commit_shas.length.to_f,
          },
        )
        publish(
          standard_event,
          schema: CopilotReviewsStandardEvent::SCHEMA,
          topic: CopilotReviewsStandardEvent::TOPIC,
          publisher: GitHub.hydro_copilot_publisher,
        )
      end
    end
  end

  subscribe("copilot.reviews.v0.DuplicateComment") do |payload|
    message = {
      retained_comment_identifier: payload[:retained_comment_identifier],
      duplicate_comment_identifier: payload[:duplicate_comment_identifier],
    }

    publish(message, schema: "copilot.reviews.v0.DuplicateComment", publisher: GitHub.hydro_copilot_publisher)
  end

  subscribe("browser.copilot.reviews.v0.ViewSession") do |payload|
    message = {
      session_id: payload[:session_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
      },
    }

    publish(message, schema: "copilot.reviews.v0.ViewSession")
  end

  subscribe("copilot.reviews.v0.RecallAnalysis") do |payload|
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        comment_id: payload[:comment_id],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
      },
      comment_source: payload[:comment_source],
      subject_reviewer_login: payload[:subject_reviewer_login],
      stage: payload[:stage],
      outcome: payload[:outcome],
      llm_judgment: payload[:llm_judgment],
      llm_confidence: payload[:llm_confidence],
      llm_comment_type: payload[:llm_comment_type],
      llm_severity: payload[:llm_severity],
      llm_ccr_comment_id: payload[:llm_ccr_comment_id],
      llm_subject_comment_id: payload[:llm_subject_comment_id],
      llm_reasoning: payload[:llm_reasoning],
      subject_review_id: payload[:ccr_review_id],
    }
    publish(message, schema: "copilot.reviews.v0.RecallAnalysis")

    if CopilotReviewsStandardEvent.dual_publish_enabled?
      # The analyzed comment is a non-subject comment, so assignment_context_for
      # (which resolves via the comment's own review) won't find a CcrDecisionRun.
      # For CCR-subject runs the analyzer passes the CCR review ID through the
      # payload; for competitor-subject runs ccr_review_id is nil, no
      # CcrDecisionRun exists, and the dual-publish path is silently skipped.
      decision_run = CopilotReviewsStandardEvent.decision_run_for_review(payload[:ccr_review_id])
      assignment_context = decision_run&.experiment_assignment_context.presence
      if !assignment_context.nil?
        standard_event = CopilotReviewsStandardEvent.build(
          event_type: "copilot_code_review_recall_analysis",
          deduplication_id: "#{payload[:request_id]}:#{payload[:comment_id]}:#{payload[:stage]}",
          pull_request_id: payload[:pull_request_id],
          tracking_id: payload[:analytics_tracking_id],
          # CCR review request_id (the decision run's response_request_id) —
          # populates `session_id`, joining recall with the other CCR events
          # for the same review. The recall analyzer's own `payload[:request_id]`
          # is a separate per-analysis id, kept in dedup + metadata.
          request_id: decision_run.response_request_id,
          primary_assignment_context: assignment_context,
          metadata: {
            "request_id" => payload[:request_id],
            "organization_id" => payload[:organization_id],
            "repository_id" => payload[:repository_id],
            "comment_id" => payload[:comment_id],
            "comment_source" => payload[:comment_source],
            "subject_reviewer_login" => payload[:subject_reviewer_login],
            "stage" => payload[:stage],
            "outcome" => payload[:outcome],
            "llm_judgment" => payload[:llm_judgment],
            "llm_confidence" => payload[:llm_confidence],
            "llm_comment_type" => payload[:llm_comment_type],
            "llm_severity" => payload[:llm_severity],
            "llm_ccr_comment_id" => payload[:llm_ccr_comment_id],
            "llm_subject_comment_id" => payload[:llm_subject_comment_id],
            "llm_reasoning" => payload[:llm_reasoning],
          },
        )
        publish(
          standard_event,
          schema: CopilotReviewsStandardEvent::SCHEMA,
          topic: CopilotReviewsStandardEvent::TOPIC,
          publisher: GitHub.hydro_copilot_publisher,
        )
      end
    end
  end
end
