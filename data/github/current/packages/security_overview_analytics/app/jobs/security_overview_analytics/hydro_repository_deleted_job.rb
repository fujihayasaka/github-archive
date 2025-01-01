# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class HydroRepositoryDeletedJob < RepositoryHydroMessageJob
    queue_as :hydro_security_overview_analytics_repository_deleted

    sig { void }
    def perform
      unless TenantValidationHelper.should_handle_repository_lifecycle_events?(repository.owner_id)
        GitHub.logger.info("Event skipped.", "code.namespace": self.class.name, "code.function": __method__)
        GitHub.dogstats.increment("security_overview_analytics.event.repository_deleted.skipped", tags: all_stats_tags)
        return
      end

      SecurityOverviewAnalytics::Repository.throttle_writes do
        SecurityOverviewAnalytics::Repository.where(repository_id:).delete_all
      end

      SecurityOverviewAnalytics::FeatureStatus.throttle_writes do
        SecurityOverviewAnalytics::FeatureStatus.where(repository_id:).delete_all
      end

      GitHub.logger.info("Event processed.", "code.namespace": self.class.name, "code.function": __method__)
      GitHub.dogstats.increment("security_overview_analytics.event.repository_deleted.processed", tags: all_stats_tags)
      instrument_repository_updated
    end
  end
end
