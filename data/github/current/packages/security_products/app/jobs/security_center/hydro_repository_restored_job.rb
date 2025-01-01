# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/repositories/v2/restored_pb"

module SecurityCenter
  class HydroRepositoryRestoredJob < HydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include LifecycleEventHandler

    queue_as :hydro_security_center_repository_restored

    retry_on_dirty_exit

    sig { void }
    def perform
      # Enqueue for full sync
      owner = repository.owner
      if owner.nil?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_found"])
        return
      end

      if owner.organization? || AdvancedSecurity::Features::User::AdvancedSecurity.new(owner).security_center_for_emus_enabled?
        SecurityCenter::RepositorySyncJob.perform_later(
          repository_id: repository_id,
          source_event: schema,
          event_timestamp: timestamp,
        )
      end

      # Notify security features
      # keeping legacy (non-hydro) event name for compatibility
      GitHub.logger.info("Notifying security features", "code.namespace": self.class.name, "code.function": __method__,)
      SecurityCenterUpdater.notify_security_features_for_repo(
        repository,
        source_event: "repo.restore",
      )

      # NOTE: Do not capture `repository_updated` metric here - we haven't updated the repository yet.
    end

    sig { override.params(error: T.untyped).returns(T::Array[String]) }
    def all_stats_tags(error: $!)
      super(error:).concat([
        "source_event:#{schema}",
      ]).compact
    end

    sig { override.returns(Integer) }
    def repository_id
      payload.repository_id
    end

    private

    sig { returns(::Hydro::Schemas::Github::Repositories::V2::Restored) }
    memoize def payload
      ::Hydro::Schemas::Github::Repositories::V2::Restored.new(message)
    end

    sig { returns(::Repository) }
    memoize def repository
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.source_event": schema,
        "gh.repo.id": repository_id,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_log_context
      super.merge({
        app: "github-security-center"
      })
    end
  end
end
