# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

module SecurityOverviewAnalytics
  class SecretScanningAlertRevisionIngestionJob < ApplicationJob
    include GitHub::Memoizer
    include LifecycleEventHandler::ActiveJob

    SecretScanningAlert = ::GitHub::Proto::SecretScanning::Metrics::V1::Alert
    SecretScanningAlertResolution = ::GitHub::Proto::SecretScanning::Types::V1::TokenResolution
    SecretScanningTokenValidity = ::GitHub::Proto::SecretScanning::Types::V1::TokenValidity

    queue_as :security_overview_analytics_secret_scanning_alert_revision_ingestion

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    RETRYABLE_ERRORS = T.let([
      ActiveRecord::RecordNotFound, # replication lag
      ActiveRecord::Deadlocked, # DB deadlock
      Freno::Error
    ], T::Array[T.class_of(StandardError)])
    # Workaround for https://sorbet.org/docs/error-reference#7019
    T.unsafe(self).retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer

    sig do
      params(
        alert: SecretScanningAlert,
        event_time: Time,
        source_event: String,
        force_rewrite: T::Boolean,
      ).void
    end
    def perform(alert:, event_time:, source_event:, force_rewrite: false)
      return unless should_perform?

      upsert_revision

      instrument_event_processed(event_time)
    end

    protected

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.id": alert.repository_id,
        "gh.security_overview_analytics.alert": alert.to_h,
        "gh.security_overview_analytics.event_time": event_time,
        "gh.repo.owner.id": repository.owner&.id,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end

    private

    sig { override.returns(String) }
    def source_event
      arguments.dig(0, :source_event)
    end

    sig { params(event_time: Time).void }
    def instrument_event_processed(event_time)
      instrument_repository_updated

      elapsed_time = (Time.now.to_f - event_time.to_f) * 1_000
      GitHub.logger.info(
        "Secret scanning lifecycle event processed",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.revision.elapsed_time": elapsed_time,
      )
    end

    sig { void }
    def upsert_revision
      alert_resolution = SecretScanningAlertRevision.to_alert_resolution(alert.resolution)
      alert_validity = SecretScanningAlertRevision.to_alert_validity(alert.validity)

      update_payload = SecretScanningAlertRevision::UpdatePayload.new(
        alert_created_at: alert.created_at&.to_time&.utc,
        alert_updated_at: alert.updated_at&.to_time&.utc,
        alert_type: alert.token_type,
        alert_type_provider: alert.token_type_provider,
        alert_type_slug: alert.slug,
        alert_resolved: alert.resolved,
        alert_resolution:,
        alert_resolved_at: alert.resolved_at&.to_time&.utc,
        alert_validity:,
        alert_bypassed: alert.bypassed,
      )

      SecretScanningAlertRevision.throttle_writes_with_retry do
        SecretScanningAlertRevision.upsert_revision(
          update_payload,
          repository_id: alert.repository_id,
          alert_number: alert.number,
          force_rewrite: force_rewrite?
        )
      end
    end

    sig { returns(SecretScanningAlert) }
    memoize def alert
      arguments.dig(0, :alert)
    end

    sig { override.returns(Time) }
    memoize def event_time
      arguments.dig(0, :event_time)
    end

    sig { returns(T::Boolean) }
    memoize def force_rewrite?
      !!arguments.dig(0, :force_rewrite)
    end

    sig { returns(::Repository) }
    memoize def repository
      ::Repositories::Public.get_active_or_deleted!(alert.repository_id)
    end

    sig { returns(T::Boolean) }
    def should_perform?
      if repository.deleted?
        GitHub.logger.info(
          "Data ingestion skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": "Repository soft-deleted.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.secret_scanning_alert_revision_ingestion.skipped",
          tags: all_stats_tags + ["reason:repository_deleted"]
        )
        return false
      end

      unless repository.owner&.organization? || repository.owner&.is_enterprise_managed?
        GitHub.logger.info(
          "Data ingestion skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": "Not org or EMU owned repository.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.secret_scanning_alert_revision_ingestion.skipped",
          tags: all_stats_tags + ["reason:not_org_or_emu_owned_repo"]
        )
        return false
      end

      owner = T.must(repository.owner)
      unless TenantValidationHelper.is_owner_in_scope?(owner)
        GitHub.logger.info(
          "Data ingestion skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": "Tenant not in scope.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.secret_scanning_alert_revision_ingestion.skipped",
          tags: all_stats_tags + ["reason:tenant_not_in_scope"]
        )
        return false
      end

      true
    end
  end
end
