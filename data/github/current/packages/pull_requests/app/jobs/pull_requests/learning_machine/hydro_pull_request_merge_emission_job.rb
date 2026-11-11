# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/v1/pull_request_merge_pb"

module PullRequests
  module LearningMachine
    # Consumes `cp1-iad.ingest.github.v1.PullRequestMerge` and re-publishes
    # a derived `pull_request_merged` StandardEvent into the PRs-owned
    # `core_productivity.analytics_pipelines.v0.StandardEvent` topic, but
    # only when the PR was reviewed by CCR (i.e. a recorded CCR decision
    # run for the PR carries a non-blank experiment assignment context).
    #
    # Out-of-process from the originating merge request — this job runs
    # off the Aqueduct→Kafka pipeline rather than the request handler.
    # See `https://github.com/github/copilot-code-review/issues/2287` for
    # the broader rationale and per-field detail.
    class HydroPullRequestMergeEmissionJob < HydroMessageJob
      include GitHub::Memoizer

      queue_as :hydro_pull_requests_learning_machine_pull_request_merge_emission

      # Recoverable / transient errors — bounded retry with backoff. Matches
      # the safety set used by SecurityOverviewAnalytics::LifecycleEventRetryHandler.
      RETRYABLE_ERRORS = T.let(
        [
          ActiveRecord::RecordNotFound,                # replication lag
          ActiveRecord::Deadlocked,                    # DB deadlock
          Freno::Error,                                # Freno throttling
          *Resiliency::Response::UnavailableExceptions, # transient DB unavailability
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

        pr = payload.pull_request
        return StandardEventEmitter.skip(reason: "no_pull_request_id", source_topic: topic) unless pr&.id && pr.id > 0
        merged_at_ts = pr.merged_at
        return StandardEventEmitter.skip(reason: "no_merged_at", source_topic: topic) unless merged_at_ts&.seconds

        merged_at = Time.at(merged_at_ts.seconds).utc

        run = StandardEventEmitter.latest_ccr_run(pr.id, before: merged_at)
        return StandardEventEmitter.skip(reason: "no_ccr_run", source_topic: topic) if run.nil?
        return StandardEventEmitter.skip(reason: "no_assignment_context", source_topic: topic) if run.experiment_assignment_context.blank?

        # All "ccr_*"-prefixed fields are sourced from the CCR review run that
        # influenced this PR's merge decision. When PRs eventually onboards
        # to ExP/LM, it can add its own PR-side metadata alongside these
        # without a naming collision.
        #
        # `request_id` (→ session_id) is the GitHub request id
        # captured on the CCR-agent review request — the same value CCR's
        # own StandardEvents carry in `session_id`, so review-time and
        # merge-time events join cleanly downstream. It is NOT the merge
        # request's id.
        StandardEventEmitter.publish(
          event_type: "pull_request_merged",
          source_topic: topic,
          deduplication_id: "pull_request_merged:#{pr.id}:#{merged_at_ts.seconds}",
          pull_request_id: pr.id,
          secondary_assignment_context: run.experiment_assignment_context.to_s,
          request_id: run.response_request_id,
          metadata: {
            "merged_at" => merged_at,
            "ccr_review_submitted_at" => run.submitted_at,
            "ccr_merge_readiness" => run.approval_readiness_code.presence,
            "ccr_pull_request_review_id" => run.pull_request_review_id,
            "ccr_response_request_id" => run.response_request_id,
          },
          measurements: {
            "ccr_decision_to_merge_seconds" => (merged_at - run.submitted_at).to_f,
          },
        )
      end

      private

      sig { returns(Hydro::Schemas::Github::V1::PullRequestMerge) }
      memoize def payload
        Hydro::Schemas::Github::V1::PullRequestMerge.new(message)
      end

      sig { override.returns(T::Hash[String, T.untyped]) }
      def logging_context
        super.merge({
          "gh.pull_request_id" => payload.pull_request&.id,
        })
      end
    end
  end
end
