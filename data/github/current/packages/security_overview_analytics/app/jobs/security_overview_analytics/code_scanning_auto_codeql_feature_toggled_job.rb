# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  class CodeScanningAutoCodeqlFeatureToggledJob < ApplicationJob
    include GitHub::Memoizer
    include GitHub::SecurityCenter::LoggingHelper
    include LifecycleEventHandler::ActiveJob
    include ::ActiveJob::InitiallyEnqueuedAt

    queue_as :security_overview_analytics_code_scanning_feature_toggled

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    RETRYABLE_EXCEPTIONS = T.let([
      CodeScanning::AutoCodeqlError,
      Faraday::TimeoutError,
    ], T::Array[T::Class[T.anything]])
    retry_on *T.unsafe(RETRYABLE_EXCEPTIONS), wait: :polynomially_longer

    locked_by timeout: 15.minutes, key: ->(job) do
      repository_id = job.arguments.dig(0, :repository_id)
      DEFAULT_LOCK_STRINGIFY_PROC.call([repository_id])
    end

    resolve_tenant_context do |args|
      repository_id = args[:repository_id]
      ::Repositories::Public.resolve_tenant(id: repository_id)
    end

    sig do
      params(
        repository_id: Integer,
        source_event: String,
      )
      .void
    end
    def perform(repository_id:, source_event:)
      unless TenantValidationHelper.should_handle_feature_enablement_events?(repository.owner)
        GitHub.logger.info(
          "Event skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.feature_status.name": :code_scanning_auto_codeql_enabled,
          "gh.security_overview_analytics.feature_status.reason_to_skip": "Ineligible repository owner."
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.event.code_scanning_auto_codeql_feature_toggled.skipped",
          tags: all_stats_tags + ["reason:ineligible_owner"]
        )
        return
      end

      # No incremental deviation reporting here.
      # Because this doesn't come from a hydro event, we have to check the source anyway.

      # There's no event for eligibility changes, and no single place (or small set of places) we could add one.
      # For now, we'll piggy back on actual enablement changes, and let reconciliation clean up the rest :(
      FeatureStatusRevision.code_scanning_auto_codeql_status(repository:) => { enabled:, eligible: }

      date_id = Date.id_from_date(event_time.utc.to_date)
      FeatureStatusRevision.throttle_writes do
        FeatureStatusRevision.upsert_feature_status(
          repository_id:,
          date_id:,
          payload: FeatureStatusRevision::UpdatePayload.new(
            code_scanning_auto_codeql_enabled: enabled,
            code_scanning_auto_codeql_eligible: eligible,
          )
        )
      end

      instrument_repository_updated
    end

    private

    sig { override.returns(T::Array[String]) }
    def stats_tags
      tags = super
      tags << "source_event:#{source_event}"
      tags
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.id": repository.id,
        "gh.owner.id": repository.owner_id,
        "gh.security_overview_analytics.source_event": source_event
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end

    sig { returns(::Repository) }
    memoize def repository
      repository_id = arguments.dig(0, :repository_id)
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { override.returns(Time) }
    def event_time
      # Since this is enqueued to run 6 hours after a PR is opened,
      # it isn't accurate to say the event time was the PR creation.
      initially_enqueued_at
    end

    sig { override.returns(String) }
    def source_event
      arguments.dig(0, :source_event)
    end
  end
end
