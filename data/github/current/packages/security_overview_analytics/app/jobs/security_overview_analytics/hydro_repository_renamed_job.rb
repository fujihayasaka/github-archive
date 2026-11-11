# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/v1/repository_rename_pb"

module SecurityOverviewAnalytics
  class HydroRepositoryRenamedJob < RepositoryHydroMessageJob
    queue_as :hydro_security_overview_analytics_repository_renamed

    sig { void }
    def perform
      if !TenantValidationHelper.should_handle_repository_lifecycle_events?(repository_owner_id)
        GitHub.logger.info("Event skipped.", "code.namespace": self.class.name, "code.function": __method__)
        GitHub.dogstats.increment("security_overview_analytics.event.repository_renamed.skipped", tags: all_stats_tags)
        return
      end

      SecurityOverviewAnalytics::Repository.throttle do
        with_write do
          SecurityOverviewAnalytics::Repository
            .where(repository_id: repository_id)
            .update_all(
              event_time:,
              name: payload.current_name,
              updated_at: Time.current
            )
        end
      end

      GitHub.logger.info("Event processed.", "code.namespace": self.class.name, "code.function": __method__)
      GitHub.dogstats.increment("security_overview_analytics.event.repository_renamed.processed", tags: all_stats_tags)
      instrument_repository_updated
    end

    protected

    sig { returns(::Hydro::Schemas::Github::V1::RepositoryRename) }
    memoize def payload
      ::Hydro::Schemas::Github::V1::RepositoryRename.new(message)
    end

    sig { returns(Integer) }
    memoize def repository_owner_id
      T.must(T.must(payload.repository).owner_id).value
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.name": payload.current_name
      })
    end
  end
end
