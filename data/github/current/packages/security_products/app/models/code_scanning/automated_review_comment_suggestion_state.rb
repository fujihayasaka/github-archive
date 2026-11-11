# typed: strict
# frozen_string_literal: true

module CodeScanning
  module AutomatedReviewCommentSuggestionState
    SUGGESTION_PENDING_DURATION_METRIC = T.let("code_scanning.automated_review_comment.suggestion_pending_duration", String)
    STALE_SUGGESTION_PENDING_METRIC = T.let("code_scanning.automated_review_comment.stale_suggestion_pending", String)
    TIMEOUT_MESSAGE = T.let("Generating the suggestion is taking longer than expected", String)

    sig { params(comment: AutomatedReviewComment).void }
    def self.start_pending!(comment)
      comment.assign_attributes(
        suggestion: nil,
        suggestion_state: :suggestion_state_pending,
        suggestion_error_message: nil,
      )
      comment.updated_at = Time.current
      comment.save!
    end

    sig do
      params(
        comment: AutomatedReviewComment,
        attributes: T::Hash[Symbol, T.untyped],
      ).void
    end
    def self.finish_pending!(comment, attributes:)
      suggestion_pending_started_at = suggestion_pending_started_at(comment)

      comment.update!(**attributes)

      return if suggestion_pending_started_at.nil?

      duration_seconds = Time.current - suggestion_pending_started_at
      GitHub.dogstats.distribution(
        SUGGESTION_PENDING_DURATION_METRIC,
        duration_seconds,
        tags: ["final_state:#{T.cast(comment.read_attribute(:suggestion_state), String)}"],
      )
    end

    sig { params(comment: AutomatedReviewComment, error_message: String).void }
    def self.finish_with_error!(comment, error_message:)
      finish_pending!(
        comment,
        attributes: {
          suggestion: nil,
          suggestion_state: :suggestion_state_error,
          suggestion_error_message: error_message,
        },
      )
    end

    sig { params(comment: AutomatedReviewComment).void }
    def self.finish_with_no_suggestion!(comment)
      finish_pending!(
        comment,
        attributes: {
          suggestion: nil,
          suggestion_state: :suggestion_state_no_suggestion,
          suggestion_error_message: nil,
        },
      )
    end

    sig { params(comment: AutomatedReviewComment, suggestion: ReviewComments::Suggestion).void }
    def self.finish_with_suggestion!(comment, suggestion:)
      finish_pending!(
        comment,
        attributes: {
          suggestion: suggestion,
          suggestion_state: :suggestion_state_present,
          suggestion_error_message: nil,
        },
      )
    rescue JSON::GeneratorError => error
      repository = T.must(comment.repository)
      if FeatureFlag.vexi.enabled?(:code_scanning_arc_suggestion_json_generator_error_handling, repository, repository.owner, default: false)
        GitHub.dogstats.increment("code_scanning.automated_review_comment.suggestion.serialization_failed")

        GitHub.logger.warn(
          "Failed to serialize JSON",
          "gh.error.class" => error.class.name,
          "gh.automated_review_comment.id" => comment.id,
          "gh.pull_request.id" => comment.pull_request_id,
          "gh.repo.id" => comment.repository_id,
        )
        comment.reload
        finish_with_error!(comment, error_message: "Failed to generate autofix suggestion")
      else
        raise
      end
    end

    sig { params(comment: AutomatedReviewComment).void }
    def self.timeout_pending!(comment)
      finish_with_error!(comment, error_message: TIMEOUT_MESSAGE)

      GitHub.dogstats.increment(STALE_SUGGESTION_PENDING_METRIC)
    end

    sig { params(comment: AutomatedReviewComment).returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def self.suggestion_pending_started_at(comment)
      return nil unless comment.read_attribute(:suggestion_state) == "suggestion_state_pending"

      comment.updated_at
    end
  end
end
