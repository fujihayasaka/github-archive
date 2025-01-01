# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  class HydroDependabotAlertRevisionJob < HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler::Hydro
    include LifecycleEventRetryHandler

    queue_as :hydro_security_overview_analytics_dependabot_alert_revision

    retry_on_dirty_exit

    Event = ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent

    SUPPORTED_ACTIONS = T.let(%w[
      create
      resolve
      dismiss
      reopen
      reintroduce
      auto_dismiss
      auto_reopen
      withdraw
      severity_change
    ].freeze, T::Array[String])

    resolve_tenant_context do |message|
      ::Repositories::Public.resolve_tenant(id: message.dig(:repository_id))
    end

    sig { void }
    def perform
      if !SUPPORTED_ACTIONS.include?(event.action)
        GitHub.dogstats.increment("security_overview_analytics.dependabot_alert_revisions.skipped", tags: all_stats_tags + ["reason:action_not_supported"])
        GitHub.logger.info("Unsupported event; skipping event", "code.namespace": self.class.name, "code.function": __method__)
        return
      end

      if event.action == "withdraw"
        unless DependabotAlertRevision.exists?(repository_id: event.repository_id, alert_number: event.repository_vulnerability_alert_number)
          GitHub.dogstats.increment("security_overview_analytics.dependabot_alert_revisions.skipped", tags: all_stats_tags + ["reason:revisions_not_found"])
          GitHub.logger.info("Withdrawn alert does not exist in data table; skipping event", "code.namespace": self.class.name, "code.function": __method__)
          return
        end

        handle_withdraw
        return
      end

      if event.action == "severity_change"
        handle_severity_update
        return
      end

      begin
        repository = ::Repositories::Public.get_active_or_deleted!(event.repository_id)
      rescue ActiveRecord::RecordNotFound => e
        if event.action == "resolve" && !RepositoryVulnerabilityAlert.exists?(id: event.repository_vulnerability_alert_id)
          # On repository hard-deletion/purge, Dependabot alerts emit an alert resolution event.
          # This is the "terminal" resolution event; both the repository and alert have been purged.
          # We should not update in this scenario.
          GitHub.logger.info("Repository and alert not found; assuming repo was purged; skipping revision", "code.namespace": self.class.name, "code.function": __method__)
          return
        else
          # Assume we've encountered replication lag, and raise an error to retry the job.
          raise e
        end
      end

      unless TenantValidationHelper.should_handle_dependabot_alert_events?(repository)
        GitHub.logger.info("Repository did not qualify for handling Dependabot alert events; skipping revision", "code.namespace": self.class.name, "code.function": __method__)
        return
      end

      DependabotAlertRevision.throttle_writes_with_retry do
        DependabotAlertRevision.upsert_revision(
          update_payload,
          repository_id: event.repository_id,
          alert_number: event.repository_vulnerability_alert_number,
        )
      end

      instrument_event_processed
    end

    sig { override.returns(T::Array[String]) }
    def all_stats_tags
      super.concat([
        "source_event:#{source_event}
      "]).compact
    end

    private

    sig { void }
    def handle_withdraw
      deleted_rows = T.let(0, Integer)
      DependabotAlertRevision.throttle_writes_with_retry do
        deleted_rows = DependabotAlertRevision.where(
          repository_id: event.repository_id,
          alert_number: event.repository_vulnerability_alert_number
        ).delete_all
      end

      # Recalculate rollup stats after purging a bunch of alert/revision data
      UpdateFeatureStatusSummaryJob.enqueue(repository_id: event.repository_id)

      instrument_withdraw_event_processed(deleted_rows:)
    end

    sig { void }
    def handle_severity_update
      update_payload = { alert_severity: event.severity }
      return unless DependabotAlertRevision.exists?(repository_id: event.repository_id, alert_number: event.repository_vulnerability_alert_number)

      updated_rows = DependabotAlertRevision.throttle_writes_with_retry do
        DependabotAlertRevision
          .where(repository_id: event.repository_id, alert_number: event.repository_vulnerability_alert_number)
          .update_all(**update_payload)
      end

      # Recalculate rollup stats after purging a bunch of alert/revision data
      UpdateFeatureStatusSummaryJob.enqueue(repository_id: event.repository_id)

      instrument_vulnerability_update_event_processed(updated_rows:)
    end

    sig { void }
    def instrument_event_processed
      instrument_repository_updated

      elapsed_time = (Time.now.to_f - timestamp) * 1_000
      GitHub.logger.info(
        "Dependabot lifecycle event processed",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.revision.elapsed_time": elapsed_time,
      )
    end

    sig { params(deleted_rows: Integer).void }
    def instrument_withdraw_event_processed(deleted_rows:)
      instrument_repository_updated

      elapsed_time = (Time.now.to_f - timestamp) * 1_000
      GitHub.dogstats.count("security_overview_analytics.dependabot_alert_revisions.deleted", deleted_rows)
      GitHub.logger.info(
        "Dependabot withdraw event processed",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.revision.elapsed_time": elapsed_time,
        "gh.security_overview_analytics.revision.deleted_rows": deleted_rows,
      )
    end

    sig { params(updated_rows: Integer).void }
    def instrument_vulnerability_update_event_processed(updated_rows:)
      instrument_repository_updated

      elapsed_time = (Time.now.to_f - timestamp) * 1_000
      GitHub.dogstats.count("security_overview_analytics.dependabot_alert_revisions.severities_updated", updated_rows)
      GitHub.logger.info(
        "Dependabot vulnerability update event processed",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.revision.elapsed_time": elapsed_time,
        "gh.security_overview_analytics.revision.updated_rows": updated_rows,
      )
    end

    sig { returns(Event) }
    memoize def event
      Event.new(message)
    end

    sig { returns(DependabotAlertRevision::UpdatePayload) }
    memoize def update_payload
      DependabotAlertRevision.create_update_payload(event)
    end

    sig { override.returns(String) }
    memoize def source_event
      # Because all changes to a Dependabot alert use the same event, we need some way to distinguish for telemetry.
      action = message.dig(:action)
      "#{schema}##{action}"
    end

    sig { override.returns(Time) }
    def event_time
      Time.at(timestamp_nano)
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge(
        "gh.repo.id": event.repository_id,
        "gh.security_overview_analytics.source_event": source_event,
        "gh.security_overview_analytics.event_action": event.action,
        "gh.security_alerts.id": event.repository_vulnerability_alert_id,
        "gh.security_alerts.number": event.repository_vulnerability_alert_number,
        "gh.security_alerts.ghsa.id": event.ghsa_id,
        "gh.security_alerts.vulnerability.id": event.vulnerability_id,
        "gh.security_alerts.vulnerable_version_range.id": event.vulnerable_version_range_id,
      )
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_log_context
      super.merge({ app: "github-security-center" })
    end
  end
end
