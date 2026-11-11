# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  class DependabotAlertRevisionIngestionJob < ApplicationJob
    include GitHub::Memoizer
    include LifecycleEventHandler::ActiveJob

    queue_as :security_overview_analytics_dependabot_alert_revision_ingestion

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    RETRYABLE_ERRORS = T.let([
      ActiveRecord::RecordNotFound, # replication lag
      ActiveRecord::Deadlocked, # DB deadlock
      Freno::Error
    ], T::Array[T.class_of(StandardError)])
    # Workaround for https://sorbet.org/docs/error-reference#7019
    T.unsafe(self).retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer

    use_replicas \
      ApplicationRecord::SecurityOverviewAnalytics,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Configurations,
      ApplicationRecord::Notify

    RepositoryVulnerabilityAlertEvent = ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent
    EventState = RepositoryVulnerabilityAlertEvent::State

    around_enqueue do |job, block|
      alert = job.arguments.dig(0, :alert)
      # Alert identifiers default to 0 if not set in the event object.
      if alert.repository_vulnerability_alert_id.zero? || alert.repository_vulnerability_alert_number.zero? || alert.repository_id.zero?
        report_upsert_skipped("missing_alert_identifier")
        clear_lock
        next
      end

      block.call
    end

    around_perform do |_, block|
      # Another tenant validation in case tenant falls out of scope between
      # when the repo job attempts to queue this job and when this job is executed
      next unless should_handle_upsert?
      block.call
    end

    sig do
      params(
        alert: RepositoryVulnerabilityAlertEvent,
        event_time: Time,
        source_event: String,
        force_rewrite: T::Boolean,
        update_severity: T.nilable(T::Boolean),
      ).void
    end
    def perform(alert:, event_time:, source_event:, force_rewrite: false, update_severity: false)
      DependabotAlertRevision.throttle_writes_with_retry do
        DependabotAlertRevision.upsert_revision(
          update_payload,
          repository_id:,
          alert_number:,
          force_rewrite:
        )

        if update_severity
          DependabotAlertRevision.update_severities(
            T.must(update_payload.alert_severity),
            repository_id:,
            alert_number:,
          )

          GitHub.logger.info("Dependabot alert severity updates completed")
        end
      end

      GitHub.logger.info("Dependabot alert upsert completed")
      GitHub.dogstats.increment(
        "security_overview_analytics.dependabot_alert_revision_ingestion.success",
        tags: all_stats_tags
      )

      instrument_repository_updated
    end

    sig { returns(T::Boolean) }
    def should_handle_upsert?
      if repository.deleted?
        report_upsert_skipped("repository_deleted")
        return false
      end

      unless repository.owner&.organization?
        report_upsert_skipped("not_org_owned_repo")
        return false
      end

      owner = T.must(repository.owner)
      unless TenantValidationHelper.is_owner_in_scope?(owner)
        report_upsert_skipped("tenant_not_in_scope")
        return false
      end

      true
    end

    private

    sig { override.returns(String) }
    def source_event
      arguments.dig(0, :source_event)
    end

    sig { params(reason: String).void }
    def report_upsert_skipped(reason)
      GitHub.logger.info(
        "Upsert skipped.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.job.reason": reason,
      )
      GitHub.dogstats.increment(
        "security_overview_analytics.dependabot_alert_revision_ingestion.skipped",
        tags: all_stats_tags + [
          "reason:#{reason.parameterize.underscore}"
        ]
      )
    end

    sig { returns(Integer) }
    memoize def repository_id
      alert.repository_id
    end

    sig { returns(::Repository) }
    memoize def repository
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { returns(Integer) }
    memoize def alert_id
      alert.repository_vulnerability_alert_id
    end

    sig { returns(RepositoryVulnerabilityAlertEvent) }
    memoize def alert
      arguments.dig(0, :alert)
    end

    sig { returns(Integer) }
    memoize def alert_number
      alert.repository_vulnerability_alert_number
    end

    sig { override.returns(Time) }
    memoize def event_time
      arguments.dig(0, :event_time)
    end

    sig { returns(DependabotAlertRevision::UpdatePayload) }
    memoize def update_payload
      DependabotAlertRevision.create_update_payload(alert)
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.id": repository_id,
        "gh.alert.number": alert_number,
        "gh.alert.id": alert_id,
        "gh.security_overview_analytics.event_time": event_time,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({ app: "github-security-center" })
    end
  end
end
