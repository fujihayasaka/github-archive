# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class HydroRepositoryCreatedJob < RepositoryHydroMessageJob
    queue_as :hydro_security_overview_analytics_repository_created

    sig { void }
    def perform
      owner_id = repository_payload[:owner_id]
      unless TenantValidationHelper.should_handle_repository_lifecycle_events?(owner_id)
        GitHub.logger.info("Event skipped.", "code.namespace": self.class.name, "code.function": __method__)
        GitHub.dogstats.increment("security_overview_analytics.event.repository_created.skipped", tags: all_stats_tags)
        return
      end

      upsert_payload = repository_payload
      SecurityOverviewAnalytics::Repository.throttle do
        with_write do
          SecurityOverviewAnalytics::Repository.upsert(upsert_payload, on_duplicate: :skip)
        end
      end

      GitHub.logger.info("Event processed.", "code.namespace": self.class.name, "code.function": __method__)
      GitHub.dogstats.increment("security_overview_analytics.event.repository_created.processed", tags: all_stats_tags)
      instrument_repository_updated
    end

    protected

    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def repository_payload
      owner_id = message.dig(:repository, :owner_id, :value)

      {
        archived: message.dig(:repository, :is_archived),
        event_time: event_time,
        name: message.dig(:repository, :name),
        organization_id: owner_id,
        owner_type: repository.owner_type,
        pushed_at: repository.pushed_at,
        repository_id: message.dig(:repository, :id),
        visibility: message.dig(:repository, :visibility).to_s.downcase,
      }.tap do |payload|
        # The column is currently required, so we're recording 0 for users
        payload[:organization_id] = 0 if repository.owner_type.downcase == "user"

        # Repository business can't be passed through payload, as it's an indirect dependency
        # Loading it from database
        payload[:business_id] = BusinessResolver.resolve_for(repository)&.id
        payload[:owner_id] = owner_id
      end
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.fork": message.dig(:repository, :is_fork),
        "gh.repo.owner.id": message.dig(:repository, :owner_id, :value),
      })
    end
  end
end
