# typed: strict
# frozen_string_literal: true

require "turboscan"

module SecurityOverviewAnalytics
  class CodeScanningAlertRevisionIngestionJob < ApplicationJob
    extend T::Sig
    include GitHub::Memoizer
    include LifecycleEventHandler::ActiveJob

    TurboscanInsightsAlert = ::Turboscan::Proto::InsightsAlert

    queue_as :security_overview_analytics_code_scanning_alert_revision_ingestion

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    RETRYABLE_ERRORS = T.let([
      ActiveRecord::RecordNotFound, # replication lag
      ActiveRecord::Deadlocked, # DB deadlock
      Freno::Error
    ], T::Array[T.class_of(StandardError)])
    # Workaround for https://sorbet.org/docs/error-reference#7019
    T.unsafe(self).retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer

    class NoAlertNumberError < StandardError; end

    sig do
      params(
        alert: TurboscanInsightsAlert,
        date_id: Integer,
        event_time: Time,
        deleted: T::Boolean,
        source_event: String,
        force_rewrite: T::Boolean,
      ).void
    end
    def perform(alert:, date_id:, event_time:, deleted:, source_event:, force_rewrite: false)
      return unless should_handle_event?

      # An ongoing bug where turboscan could return 0 for alert number - https://github.com/github/code-scanning/issues/14767
      if alert.number == 0
        GitHub.logger.warn(
          "Found an alert without number.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository_id,
          "gh.security_overview_analytics.feature_type": CodeScanningAlertRevision.feature_type,
          "gh.security_overview_analytics.revision.alert_id": alert.id,
          "gh.security_overview_analytics.revision.date": date_id,
        )

        GitHub.dogstats.increment("security_overview_analytics.code_scanning.alert_without_number")

        raise NoAlertNumberError
      end

      if deleted
        CodeScanningAlertRevision.delete_revisions(
          repository_id:,
          alert_number:,
          alert_id:,
        )
      else
        CodeScanningAlertRevision.throttle_writes_with_retry do
          CodeScanningAlertRevision.upsert_revision(
            update_payload,
            repository_id:,
            alert_number:,
            date_id:,
            force_rewrite:,
            alert_id:,
          )
        end
      end

      instrument_repository_updated
    end

    protected

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.id": repository_id,
        "gh.security_overview_analytics.date_id": date_id,
        "gh.security_overview_analytics.event_time": event_time,
        "gh.security_overview_analytics.alert": alert,
        "gh.security_overview_analytics.alert_deleted": alert_deleted?,
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

    sig { returns(Integer) }
    memoize def date_id
      arguments.dig(0, :date_id)
    end

    sig { override.returns(Time) }
    memoize def event_time
      arguments.dig(0, :event_time)
    end

    sig { returns(T::Boolean) }
    memoize def alert_deleted?
      arguments.dig(0, :deleted)
    end

    sig { returns(TurboscanInsightsAlert) }
    memoize def alert
      arguments.dig(0, :alert)
    end

    sig { returns(Integer) }
    memoize def repository_id
      alert.repository_id
    end

    sig { returns(Integer) }
    memoize def alert_number
      if CodeScanningAlertRevision.write_alert_number?(T.must(repository), organization)
        alert.number
      else
        alert.id
      end
    end

    sig { returns(T.nilable(Integer)) }
    memoize def alert_id
      alert.id if CodeScanningAlertRevision.read_alert_id?(T.must(repository), organization)
    end

    sig { returns(T.nilable(::Repository)) }
    memoize def repository
      return nil unless repository_id.positive?
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { returns(::Organization) }
    memoize def organization
      T.must(Organization.find_by(id: repository&.owner_id))
    end

    sig { returns(T::Boolean) }
    def should_handle_event?
      unless repository.present?
        GitHub.logger.info(
          "Data ingestion skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.reason": "Repository not found.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.code_scanning_alert_revision_ingestion.skipped",
          tags: all_stats_tags + ["reason:repository_not_found"]
        )
        return false
      end

      if repository&.deleted?
        GitHub.logger.info(
          "Data ingestion skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.reason": "Repository soft-deleted.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.code_scanning_alert_revision_ingestion.skipped",
          tags: all_stats_tags + ["reason:repository_deleted"]
        )
        return false
      end

      unless TenantValidationHelper.should_handle_code_scanning_alert_events?(repository&.owner)
        GitHub.logger.info(
          "Data ingestion skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": "Tenant not in scope.",
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.code_scanning_alert_revision_ingestion.skipped",
          tags: all_stats_tags + ["reason:tenant_not_in_scope"]
        )
        return false
      end

      true
    end

    sig { returns(CodeScanningAlertRevision::UpdatePayload) }
    def update_payload
      resolution = alert.resolution
      CodeScanningAlertRevision::UpdatePayload.new(
        alert_created_at: alert.created_at&.to_time&.utc,
        alert_updated_at: alert.updated_at&.to_time&.utc,
        alert_severity:
          if alert.severity.is_a?(Symbol) && alert.severity != :NO_SECURITY_SEVERITY
            alert.severity.to_s
          end,
        tool: alert.tool_name,
        rule_sarif_identifier: alert.rule_sarif_identifier,
        alert_resolved: alert.closed,
        alert_resolved_at: alert.closed_at&.to_time&.utc,
        alert_resolution: \
          if resolution.is_a?(Symbol) && resolution != :NO_RESOLUTION
            ::Turboscan::Proto::ResultResolution.resolve(resolution)&.to_i
          end,
        alert_id: alert.id,
      )
    end
  end
end
