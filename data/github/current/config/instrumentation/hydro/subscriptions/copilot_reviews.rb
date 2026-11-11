# typed: true
# frozen_string_literal: true

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
      comment_creation_status: payload[:comment_creation_status]
    }

    publish(message, schema: "copilot.reviews.v0.ReviewCommentPersistenceMapping")
  end

  subscribe("copilot.reviews.v0.RestrictedReviewCommentPersistenceMapping") do |payload|
    message = {
      generated_comment_uuid: payload[:generated_comment_uuid],
      comment_id: payload[:comment_id],
      comment_creation_status: payload[:comment_creation_status]
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

  subscribe("copilot.reviews.v0.SuggestionAnalysis") do |payload|
    message = {
      request_id: payload[:request_id],
      context: {
        organization_id: payload[:organization_id],
        repository_id: payload[:repository_id],
        pull_request_id: payload[:pull_request_id],
        comment_id: payload[:comment_id],
        user_analytics_tracking_id: payload[:analytics_tracking_id],
      },
      fully_applied:  payload[:fully_applied],
      levenshtein_distance: payload[:levenshtein_distance],
      needleman_distance: payload[:needleman_distance],
      language: payload[:language]
    }

    publish(message, schema: "copilot.reviews.v0.SuggestionAnalysis")
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
      llm_error: payload[:llm_error]
    }
    publish(message, schema: "copilot.reviews.v0.CommentAnalysis")
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
end
