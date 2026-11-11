# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/v1/pull_request_review_submit_pb"

module PullRequests
  module LearningMachine
    # Consumes `cp1-iad.ingest.github.v1.PullRequestReviewSubmit` and
    # re-publishes a derived `pull_request_review_submitted` StandardEvent
    # when a human reviewer requests changes on a PR that CCR had reviewed.
    #
    # Only emits for CHANGES_REQUESTED reviews from non-CCR reviewers —
    # measures "did a human disagree with what CCR approved?"
    #
    # See `https://github.com/github/copilot-code-review/issues/2288`.
    class HydroPullRequestReviewSubmitEmissionJob < HydroMessageJob
      include GitHub::Memoizer

      queue_as :hydro_pull_requests_learning_machine_pull_request_review_submit_emission

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

        review = payload.pull_request_review
        return StandardEventEmitter.skip(reason: "no_review_id", source_topic: topic) unless review&.id && review.id > 0
        return StandardEventEmitter.skip(reason: "not_changes_requested", source_topic: topic) unless review.state == :CHANGES_REQUESTED

        # Skip reviews authored by CCR's own bot — CCR can submit
        # CHANGES_REQUESTED when auto-reject is enabled (private preview).
        # Cheap lookup (in-memory registry, no DB).
        copilot_bot_id = T.let(
          Apps::Privileged.integration(:copilot_pull_request_reviewer)&.bot&.id,
          T.nilable(Integer),
        )
        return StandardEventEmitter.skip(reason: "reviewer_is_ccr_bot", source_topic: topic) if copilot_bot_id && review.user_id == copilot_bot_id

        pr = payload.pull_request
        return StandardEventEmitter.skip(reason: "no_pull_request_id", source_topic: topic) unless pr&.id && pr.id > 0

        submitted_at_ts = review.submitted_at
        return StandardEventEmitter.skip(reason: "no_submitted_at", source_topic: topic) unless submitted_at_ts&.seconds
        submitted_at = Time.at(submitted_at_ts.seconds).utc

        run = StandardEventEmitter.latest_ccr_run(pr.id, before: submitted_at)
        return StandardEventEmitter.skip(reason: "no_ccr_run", source_topic: topic) if run.nil?
        return StandardEventEmitter.skip(reason: "no_assignment_context", source_topic: topic) if run.experiment_assignment_context.blank?

        StandardEventEmitter.publish(
          event_type: "pull_request_review_submitted",
          source_topic: topic,
          deduplication_id: "pull_request_review_submitted:#{review.id}",
          pull_request_id: pr.id,
          secondary_assignment_context: run.experiment_assignment_context.to_s,
          request_id: run.response_request_id,
          metadata: {
            "review_submitted_at" => submitted_at,
            # Derived from the actual review state (proto enum, preserved as
            # UPPER_SNAKE_CASE to match the proto vocabulary). Today the
            # `not_changes_requested` gate above guarantees this is always
            # "CHANGES_REQUESTED", but emitting the real value future-proofs
            # downstream consumers for when that gate is relaxed (PRs team
            # will own this event broader-scoped).
            "review_state" => review.state.to_s,
            # Reviewer identity preserved so consumers can filter out the CCR
            # bot themselves once the `reviewer_is_ccr_bot` gate is relaxed.
            # Guard against proto-default 0 (ghost user / unset) so the key
            # is absent rather than ambiguously set to "0".
            "reviewer_user_id" => review.user_id.positive? ? review.user_id : nil,
            "ccr_review_submitted_at" => run.submitted_at,
            "ccr_merge_readiness" => run.approval_readiness_code.presence,
            "ccr_pull_request_review_id" => run.pull_request_review_id,
            "ccr_response_request_id" => run.response_request_id,
          },
          measurements: {
            "ccr_decision_to_review_seconds" => (submitted_at - run.submitted_at).to_f,
          },
        )
      end

      private

      sig { returns(Hydro::Schemas::Github::V1::PullRequestReviewSubmit) }
      memoize def payload
        Hydro::Schemas::Github::V1::PullRequestReviewSubmit.new(message)
      end

      sig { override.returns(T::Hash[String, T.untyped]) }
      def logging_context
        super.merge({
          "gh.pull_request_id" => payload.pull_request&.id,
          "gh.pull_request_review_id" => payload.pull_request_review&.id,
        })
      end
    end
  end
end
