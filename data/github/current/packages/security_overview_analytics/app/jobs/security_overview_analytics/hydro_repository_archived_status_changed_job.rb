# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class HydroRepositoryArchivedStatusChangedJob < RepositoryHydroMessageJob
    queue_as :hydro_security_overview_analytics_repository_archived_status_changed

    sig { void }
    def perform
      unless TenantValidationHelper.should_handle_repository_lifecycle_events?(repository.owner_id)
        GitHub.logger.info("Event skipped.", "code.namespace": self.class.name, "code.function": __method__)
        GitHub.dogstats.increment("security_overview_analytics.event.repository_archived_status_changed.skipped", tags: all_stats_tags)
        return
      end

      SecurityOverviewAnalytics::Repository.throttle do
        with_write do
          SecurityOverviewAnalytics::Repository
            .where(repository_id:)
            .update_all(
              archived: is_archived,
              event_time: event_time,
              updated_at: Time.current
            )
        end
      end

      GitHub.logger.info("Event processed.", "code.namespace": self.class.name, "code.function": __method__)
      GitHub.dogstats.increment("security_overview_analytics.event.repository_archived_status_changed.processed", tags: all_stats_tags)
      instrument_repository_updated
    end

    sig { returns(T::Boolean) }
    memoize def is_archived
      message.dig(:is_archived)
    end

    protected

    sig { override.returns(String) }
    memoize def source_event
      action = is_archived ? "archived" : "unarchived"
      "#{schema}##{action}"
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.archived": is_archived
      })
    end
  end
end
