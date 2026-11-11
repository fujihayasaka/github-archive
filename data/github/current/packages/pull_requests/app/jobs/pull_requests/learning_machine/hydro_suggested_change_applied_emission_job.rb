# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/v1/suggested_change_applied_pb"

module PullRequests
  module LearningMachine
    # Consumes `cp1-iad.ingest.github.v1.SuggestedChangeApplied` and
    # re-publishes a derived `pull_request_suggested_change_applied`
    # StandardEvent when a user applies a suggestion from a CCR review.
    #
    # Measures CCR's suggestion-application rate — a product metric
    # distinct from approval-accuracy.
    #
    # See `https://github.com/github/copilot-code-review/issues/2289`.
    class HydroSuggestedChangeAppliedEmissionJob < HydroMessageJob
      include GitHub::Memoizer

      queue_as :hydro_pull_requests_learning_machine_suggested_change_applied_emission

      RETRYABLE_ERRORS = T.let(
        [
          ActiveRecord::RecordNotFound,
          ActiveRecord::Deadlocked,
          Freno::Error,
          *Resiliency::Response::UnavailableExceptions,
        ],
        T::Array[T.class_of(StandardError)],
      )

      retry_on_dirty_exit
      RETRYABLE_ERRORS.each do |error_class|
        retry_on error_class, delay: :polynomially_longer
      end
      discard_on(Hydro::Sink::MessagesTooLarge)

      sig { void }
      def perform
        repo = payload.repository
        return StandardEventEmitter.skip(reason: "no_repository_id", source_topic: topic) unless repo&.id && repo.id > 0
        return StandardEventEmitter.skip(reason: "emission_disabled", source_topic: topic) unless StandardEventEmitter.enabled?

        comment = payload.comment
        return StandardEventEmitter.skip(reason: "no_comment_id", source_topic: topic) unless comment&.id && comment.id > 0

        pr = payload.pull_request
        return StandardEventEmitter.skip(reason: "no_pull_request_id", source_topic: topic) unless pr&.id && pr.id > 0

        # Only emit for suggestions authored by CCR's bot — measures CCR's
        # suggestion-application rate specifically. When PRs fully onboards
        # to LM/ExP, this filter will likely be relaxed to include all
        # suggestion authors, broadening the event to cover the full
        # suggested-change surface. Cheap lookup (in-memory registry, no DB).
        copilot_bot_id = T.let(
          Apps::Privileged.integration(:copilot_pull_request_reviewer)&.bot&.id,
          T.nilable(Integer),
        )
        return StandardEventEmitter.skip(reason: "comment_not_ccr_authored", source_topic: topic) unless copilot_bot_id && comment.author_id == copilot_bot_id

        # Only emit for successful applications — the SuggestedChangeApplied
        # event also fires for failed attempts (viewer unauthorized, outdated
        # diff, etc). :UNKNOWN is the proto default / success case. When PRs
        # onboards, failed attempts may become interesting metadata rather
        # than a skip condition.
        return StandardEventEmitter.skip(reason: "apply_failed", source_topic: topic) unless payload.error == :UNKNOWN

        # Walk comment → review → CcrDecisionRunStore to resolve the
        # assignment context. Uses a PK lookup on PullRequestReviewComment
        # to get the review_id, then resolves the run via CcrDecisionRunStore.
        # Also reads the CCRA-generated identifier from the associated
        # AutomatedReviewComment (set at persistence time) so consumers can
        # correlate this event with CCRA-emitted ReviewComment events
        # without a join.
        review_comment_record = PullRequestReviewComment.find_by(id: comment.id)
        review_id = review_comment_record&.pull_request_review_id
        return StandardEventEmitter.skip(reason: "comment_not_found", source_topic: topic) unless review_id

        run = ::PullRequests::Copilot::CcrDecisionRunStore.run_for_pull_request_review_id(
          pull_request_review_id: review_id,
        )
        return StandardEventEmitter.skip(reason: "no_ccr_run", source_topic: topic) if run.nil?
        return StandardEventEmitter.skip(reason: "no_assignment_context", source_topic: topic) if run.experiment_assignment_context.blank?

        commit_sha_value = payload.commit_sha&.value
        comment_created_at_ts = comment.created_at
        # CCRA-generated comment identifier (GUID), persisted on the associated
        # AutomatedReviewComment at comment-creation time. Nil for any
        # pre-AutomatedReviewComment-era rows.
        comment_identifier = review_comment_record.automated_review_comment&.resource_id&.presence

        StandardEventEmitter.publish(
          event_type: "pull_request_suggested_change_applied",
          source_topic: topic,
          deduplication_id: "pull_request_suggested_change_applied:#{comment.id}:#{commit_sha_value || comment_created_at_ts&.seconds}",
          pull_request_id: pr.id,
          secondary_assignment_context: run.experiment_assignment_context.to_s,
          comment_identifier: comment_identifier,
          request_id: run.response_request_id,
          metadata: {
            "comment_id" => comment.id,
            # Comment author identity preserved so consumers can filter to
            # Copilot-authored themselves once the `comment_not_ccr_authored`
            # gate is relaxed (PRs team will own this event broader-scoped).
            # Guard against proto-default 0 (ghost / deleted user) so the
            # key is absent rather than ambiguously set to "0".
            "comment_author_id" => comment.author_id.positive? ? comment.author_id : nil,
            # CCRA-generated comment identifier (mirrors `comment_identifier`
            # on `copilot.reviews.v0.ReviewComment`), persisted on the
            # associated AutomatedReviewComment at comment-creation time.
            # Nil for any pre-AutomatedReviewComment-era rows; dropped via
            # `metadata.compact`.
            "comment_identifier" => comment_identifier,
            "file_extension" => payload.file_extension.presence,
            "comment_created_at" => comment_created_at_ts ? Time.at(comment_created_at_ts.seconds).utc : nil,
            # Apply outcome from the proto enum. Today the `apply_failed` gate
            # guarantees this is always "UNKNOWN" (proto default = success),
            # but emitting the real value future-proofs downstream consumers
            # for when that gate is relaxed.
            "apply_error" => payload.error.to_s,
            "ccr_response_request_id" => run.response_request_id,
          },
          conditions: {
            "comment_contains_suggestion" => !!comment.contains_suggestion,
          },
        )
      end

      private

      sig { returns(Hydro::Schemas::Github::V1::SuggestedChangeApplied) }
      memoize def payload
        Hydro::Schemas::Github::V1::SuggestedChangeApplied.new(message)
      end

      sig { override.returns(T::Hash[String, T.untyped]) }
      def logging_context
        super.merge({
          "gh.pull_request_id" => payload.pull_request&.id,
          "gh.comment_id" => payload.comment&.id,
        })
      end
    end
  end
end
