# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class HydroRepositoryVisibilityChangedJob < RepositoryHydroMessageJob
    queue_as :hydro_security_overview_analytics_repository_visibility_changed

    sig { void }
    def perform
      unless TenantValidationHelper.should_handle_repository_lifecycle_events?(repository.owner_id)
        GitHub.logger.info("Event skipped.", "code.namespace": self.class.name, "code.function": __method__)
        GitHub.dogstats.increment("security_overview_analytics.event.repository_visibility_changed.skipped", tags: all_stats_tags)
        return
      end

      SecurityOverviewAnalytics::Repository.throttle do
        with_write do
          SecurityOverviewAnalytics::Repository
            .where(repository_id:)
            .update_all(
              visibility: new_visibility,
              event_time: event_time,
              updated_at: Time.current
            )
        end
      end

      GitHub.logger.info("Event processed.", "code.namespace": self.class.name, "code.function": __method__)
      GitHub.dogstats.increment("security_overview_analytics.event.repository_visibility_changed.processed", tags: all_stats_tags)
      instrument_repository_updated
    end

    protected

    sig { returns(String) }
    memoize def new_visibility
      message.dig(:new_visibility).to_s.downcase
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.visibility": new_visibility
      })
    end
  end
end
