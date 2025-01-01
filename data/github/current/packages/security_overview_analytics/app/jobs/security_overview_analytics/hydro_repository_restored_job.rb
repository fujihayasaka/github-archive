# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class HydroRepositoryRestoredJob < RepositoryHydroMessageJob
    queue_as :hydro_security_overview_analytics_repository_restored

    sig { void }
    def perform
      unless TenantValidationHelper.should_handle_repository_lifecycle_events?(repository.owner_id)
        GitHub.logger.info("Event skipped.", "code.namespace": self.class.name, "code.function": __method__)
        GitHub.dogstats.increment("security_overview_analytics.event.repository_restored.skipped", tags: all_stats_tags)
        return
      end

      upsert_payload = repository_payload
      SecurityOverviewAnalytics::Repository.throttle do
        with_write do
          SecurityOverviewAnalytics::Repository.upsert(upsert_payload, on_duplicate: :skip)
        end
      end

      queue_to_reinitialize_alert_revisions

      GitHub.logger.info("Event processed.", "code.namespace": self.class.name, "code.function": __method__)
      GitHub.dogstats.increment("security_overview_analytics.event.repository_restored.processed", tags: all_stats_tags)
      instrument_repository_updated
    end

    protected

    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def repository_payload
      {
        archived: repository.archived?,
        event_time:,
        name: repository.name,
        organization_id: repository.owner_id,
        owner_type: repository.owner_type,
        repository_id: repository.id,
        visibility: repository.visibility,
      }.tap do |payload|
        # The column is currently required, so we're recording 0 for users
        payload[:organization_id] = 0 if repository.owner_type.downcase == "user"

        payload[:business_id] = BusinessResolver.resolve_for(repository)&.id
        payload[:owner_id] = repository.owner_id
      end
    end

    sig { void }
    def queue_to_reinitialize_alert_revisions
      Initialization::Repositories::CodeScanningAlertsJob.perform_later(repository_id:)
      Fanout::Initialization::CodeScanningPullRequestAlertsJob.perform_later(repository_id:, last_session_locked_at: nil)
      Initialization::Repositories::SecretScanningAlertsJob.perform_later(repository_id:)
      Initialization::Repositories::DependabotAlertsJob.perform_later(repository_id:)
    end
  end
end
