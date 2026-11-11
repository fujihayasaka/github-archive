# typed: true
# frozen_string_literal: true

require "hydro/schemas/github/repositories/v1/pushed_pb"

module SecurityOverviewAnalytics
  class HydroRepositoryPushedJob < RepositoryHydroMessageJob
    queue_as :hydro_security_overview_analytics_repository_pushed

    # Errors that can be logged and ignored.
    IGNORABLE_ERRORS = T.let([
      Errno::ETIMEDOUT,
    ].freeze, T::Array[T::Class[T.anything]])

    sig { void }
    def perform
      if wiki?
        GitHub.dogstats.increment("security_overview_analytics.event.repository_pushed.skipped", tags: all_stats_tags + ["reason:wiki"])
        return
      end

      unless TenantValidationHelper.should_handle_repository_lifecycle_events?(repository.owner_id)
        GitHub.logger.info("Event skipped.", "code.namespace": self.class.name, "code.function": __method__)
        GitHub.dogstats.increment("security_overview_analytics.event.repository_pushed.skipped", tags: all_stats_tags + ["reason:ineligible_owner"])
        return
      end

      SecurityOverviewAnalytics::Repository.throttle_writes do
        # Using update_all here to generate SQL directly against the DB.
        # This avoids needing to load the record or check for existence.
        SecurityOverviewAnalytics::Repository
          .where(repository_id:)
          .update_all(
            pushed_at:,
            updated_at: Time.current,
          )
      end

      GitHub.logger.info("Event processed.", "code.namespace": self.class.name, "code.function": __method__)
      GitHub.dogstats.increment("security_overview_analytics.event.repository_pushed.processed", tags: all_stats_tags)
      instrument_repository_updated
    rescue *IGNORABLE_ERRORS => e
      GitHub.logger.warn("Error updating repository last push.", e)
      GitHub.dogstats.increment("security_overview_analytics.updated.error", tags: all_stats_tags(error: e))
    end

    private

    sig { returns(::Hydro::Schemas::Github::Repositories::V1::Pushed) }
    memoize def payload
      ::Hydro::Schemas::Github::Repositories::V1::Pushed.new(message)
    end

    sig { returns(T.nilable(Time)) }
    memoize def pushed_at
      payload.pushed_at&.to_time
    end

    sig { returns(T::Boolean) }
    def wiki?
      # `path` is the file system path of the git repository
      # wiki repos always end in ".wiki.git"
      # e.g. /data/repositories/7/nw/71/43/b3/32399/2138199.wiki.git
      payload.path.end_with?(".wiki.git")
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.source_event": schema,
        "gh.repo.id": repository_id,
        "gh.repo.pushed_at": pushed_at,
      })
    end
  end
end
