# typed: strict
# frozen_string_literal: true

module PullRequests
  module LearningMachine
    # Helper for building and publishing PRs Learning Machine `StandardEvent`
    # messages onto the `core_productivity.analytics_pipelines.v0.StandardEvent`
    # topic, plus a Copilot::KV lookup for the most recent CCR decision run
    # on a given pull request.
    #
    # Used by sibling jobs in `pull_requests/app/jobs/pull_requests/learning_machine/`.
    # Kept package-local for now; if a third caller in another package wants
    # the same shape, extraction to a shared location becomes obvious.
    #
    # See `https://github.com/github/copilot-code-review/issues/2286` for
    # the broader plan and per-event field mapping.
    module StandardEventEmitter
      EVENT_VERSION = "0.0.1"
      OWNING_SERVICE = "core-productivity"
      SCHEMA = "hydro.schemas.analytics_pipelines.v0.StandardEvent"
      TOPIC = "core_productivity.analytics_pipelines.v0.StandardEvent"
      GITHUB_PULL_REQUEST_ID = "github_pull_request_id"

      # Returns true when emission should actually publish. Production-only
      # (no GHES, no Proxima).
      sig { returns(T::Boolean) }
      def self.enabled?
        return false if GitHub.enterprise?
        return false if GitHub.multi_tenant_enterprise?

        true
      end

      # Look up the most recent CCR decision run for a given pull request,
      # optionally filtered to runs that landed before `before`. Reads the
      # CCR-owned `CcrDecisionRunStore` (Copilot::KV-backed); no MySQL touch.
      #
      # Returns nil when the lookup fails or no runs exist — callers MUST
      # treat nil as "do not emit."
      sig do
        params(
          pull_request_id: Integer,
          before: T.nilable(Time),
        ).returns(T.nilable(::PullRequests::Copilot::CcrDecisionRunStore::DecisionRun))
      end
      def self.latest_ccr_run(pull_request_id, before: nil)
        runs = ::PullRequests::Copilot::CcrDecisionRunStore.runs_for_pull_request(
          pull_request_id: pull_request_id,
        )
        runs = runs.select { |run| run.submitted_at < before } if before
        runs.last
      rescue StandardError => boom
        GitHub.dogstats.increment(
          "pull_requests.learning_machine.latest_ccr_run.error",
          tags: ["error:#{boom.class.name.to_s.underscore}"],
        )
        nil
      end

      # Increments the shared `skipped` dogstats counter when a job decides
      # not to publish a StandardEvent. Tagged with `topic:` (the calling
      # job's source Hydro topic) and `reason:` (the specific gate that
      # short-circuited the job).
      #
      # All three PRs Learning Machine jobs report into a single time series
      # — partition by topic to see per-job behavior, partition by reason to
      # diagnose which gate is dropping events.
      sig { params(reason: String, source_topic: String).void }
      def self.skip(reason:, source_topic:)
        GitHub.dogstats.increment(
          "pull_requests.learning_machine.standard_event.skipped",
          tags: ["topic:#{source_topic}", "reason:#{reason}"],
        )
      end

      # Builds a StandardEvent message hash matching
      # `hydro.schemas.analytics_pipelines.v0.StandardEvent` and publishes
      # it to the PRs-owned analytics-pipelines topic. `metadata` values
      # are coerced to strings; nils are dropped. Until PRs has its own
      # ExP/LM assignment context, `primary_assignment_context` is always
      # empty; callers carry CCR's context in `secondary_assignment_context`.
      #
      # `source_topic` is the Hydro topic the calling job consumes (e.g.
      # `github.v1.PullRequestMerge`). It's used as a tag on the shared
      # `published` dogstats metric so all 3 PRs Learning Machine jobs
      # report into a single time series differentiated by topic.
      #
      # `comment_identifier` is the CCRA-generated comment GUID (only present
      # for comment-scoped events such as suggested-change-applied); it
      # populates `activity_correlation_id`. `request_id` is the CCR review
      # request_id and populates `session_id`, joining these events with the
      # CCR- and CCRA-emitted StandardEvents that carry the same value.
      sig do
        params(
          event_type: String,
          source_topic: String,
          deduplication_id: String,
          pull_request_id: Integer,
          secondary_assignment_context: String,
          comment_identifier: T.nilable(String),
          request_id: T.nilable(String),
          metadata: T::Hash[String, T.untyped],
          conditions: T::Hash[String, T::Boolean],
          measurements: T::Hash[String, Float],
        ).returns(T.untyped)
      end
      def self.publish(
        event_type:,
        source_topic:,
        deduplication_id:,
        pull_request_id:,
        secondary_assignment_context:,
        comment_identifier: nil,
        request_id: nil,
        metadata: {},
        conditions: {},
        measurements: {}
      )
        message = {
          event_type: event_type,
          owning_service: OWNING_SERVICE,
          occurred_at: Time.now.utc,
          deduplication_id: deduplication_id,
          event_version: EVENT_VERSION,
          activity_correlation_id: comment_identifier.presence,
          session_id: request_id.presence,
          primary_assignment_context: "",
          secondary_assignment_context: secondary_assignment_context.presence,
          primary_entity_id: pull_request_id.to_s,
          primary_entity_id_type: GITHUB_PULL_REQUEST_ID,
          measurements: measurements,
          conditions: conditions.merge("from_dotcom" => true),
          metadata: metadata.compact.transform_values { |v| serialize_metadata_value(v) },
        }

        result = GitHub.hydro_publisher.publish(message, schema: SCHEMA, topic: TOPIC)
        GitHub.dogstats.increment(
          "pull_requests.learning_machine.standard_event.published",
          tags: ["topic:#{source_topic}"],
        )
        result
      end

      sig { params(value: T.untyped).returns(String) }
      def self.serialize_metadata_value(value)
        case value
        when Time, DateTime
          value.utc.iso8601
        when Date
          value.iso8601
        else
          value.to_s
        end
      end
      private_class_method :serialize_metadata_value
    end
  end
end
