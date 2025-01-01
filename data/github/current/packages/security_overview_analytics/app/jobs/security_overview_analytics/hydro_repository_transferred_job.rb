# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/repositories/v1/transferred_pb"

module SecurityOverviewAnalytics
  class HydroRepositoryTransferredJob < RepositoryHydroMessageJob
    queue_as :hydro_security_overview_analytics_repository_transferred

    sig { void }
    def perform
      GitHub.logger.with_named_tags(
        "gh.repo.previous_owner.in_scope": was_previously_in_scope?,
        "gh.repo.new_owner.in_scope": is_in_scope?
      ) do
        if is_in_scope?
          upsert_soa_repo
          queue_to_reinitialize_alert_revisions unless was_previously_in_scope?
        elsif was_previously_in_scope?
          delete_soa_repo
        end

        event_skipped = !was_previously_in_scope? && !is_in_scope?
        GitHub.logger.info(
          "Event #{event_skipped ? "skipped" : "processed"}",
          "code.namespace": self.class.name,
          "code.function": __method__,
        )

        tags = all_stats_tags + [
          "previous_owner_in_scope:#{was_previously_in_scope?}",
          "new_owner_in_scope:#{is_in_scope?}"
        ]

        GitHub.dogstats.increment(
          "security_overview_analytics.event.repository_transferred.#{event_skipped ? "skipped" : "processed"}",
          tags:
        )
        instrument_repository_updated
      end
    end

    protected

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.previous_owner.id": T.must(payload.previous_owner).id,
        "gh.repo.new_owner.id": T.must(payload.new_owner).id
      })
    end

    sig { returns(::Hydro::Schemas::Github::Repositories::V1::Transferred) }
    memoize def payload
      ::Hydro::Schemas::Github::Repositories::V1::Transferred.new(message)
    end

    sig { returns(T::Boolean) }
    memoize def was_previously_in_scope?
      TenantValidationHelper.should_handle_repository_lifecycle_events?(T.must(payload.previous_owner).id)
    end

    sig { returns(T::Boolean) }
    memoize def is_in_scope?
      TenantValidationHelper.should_handle_repository_lifecycle_events?(T.must(payload.new_owner).id)
    end

    sig { void }
    def delete_soa_repo
      SecurityOverviewAnalytics::Repository.throttle_writes do
        SecurityOverviewAnalytics::Repository.where(repository_id:).delete_all
      end
      SecurityOverviewAnalytics::FeatureStatus.throttle_writes do
        SecurityOverviewAnalytics::FeatureStatus.where(repository_id:).delete_all
      end
    end

    sig { void }
    def upsert_soa_repo
      upsert_payload = repository_payload
      SecurityOverviewAnalytics::Repository.throttle_writes do
        SecurityOverviewAnalytics::Repository.upsert_all( # rubocop:disable GitHub/UpsertAll
          [upsert_payload],
          update_only: upsert_payload.keys.excluding(:repository_id)
        )
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    memoize def repository_payload
      new_owner = T.must(payload.new_owner)
      new_owner_type = new_owner.type

      {
        archived: repository.archived?,
        event_time:,
        name: payload.new_name,
        organization_id: new_owner.id,
        owner_type: new_owner_type,
        repository_id:,
        visibility: payload.new_visibility.to_s.downcase,
      }.tap do |upsert_payload|
        # The column is currently required, so we're recording 0 for users
        upsert_payload[:organization_id] = 0 if new_owner_type.to_s.downcase == "user"

        upsert_payload[:owner_id] = new_owner.id

        upsert_payload[:business_id] = BusinessResolver.resolve_for(repository)&.id
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
