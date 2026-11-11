# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/v1/repository_archived_status_changed_pb"

module SecurityCenter
  class HydroRepositoryArchivedStatusChangedJob < HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_repository_archived_status_changed

    retry_on_dirty_exit

    sig { void }
    def perform
      if repository.deleted?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:repo_deleted"])
        return
      end

      owner = repository.owner
      if owner.nil?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_found"])
        return
      end

      unless owner.organization? || AdvancedSecurity::Features::User::AdvancedSecurity.new(owner).security_center_for_emus_enabled?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_eligible"])
        return
      end

      config = RepositorySecurityCenterConfig.find_by(repository_id:)
      raise RepositoryConfigNotFound if config.nil?

      config.archived = payload.is_archived
      RepositorySecurityCenterConfig.throttle_writes { config.save! }

      GitHub.logger.info("Notifying security features", "code.namespace": self.class.name, "code.function": __method__,)
      SecurityCenterUpdater.notify_security_features_for_repo(
        repository,
        # keeping legacy (non-hydro) event names for compatibility
        source_event: payload.is_archived ? "repo.archived" : "repo.unarchived",
      )

      instrument_repository_updated
    end

    sig { override.params(error: T.untyped).returns(T::Array[String]) }
    def all_stats_tags(error: $!)
      super(error:).concat([
        "source_event:#{source_event}",
      ]).compact
    end

    sig { override.returns(Integer) }
    def repository_id
      payload.repository_id
    end

    private

    sig { returns(::Hydro::Schemas::Github::V1::RepositoryArchivedStatusChanged) }
    memoize def payload
      ::Hydro::Schemas::Github::V1::RepositoryArchivedStatusChanged.new(message)
    end

    sig { returns(::Repository) }
    memoize def repository
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { returns(String) }
    memoize def source_event
      # Because the same topic/schema is used for both archived/unarchived, we need some way to distinguish for telemetry.
      action = payload.is_archived ? "archived" : "unarchived"
      "#{schema}##{action}"
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.source_event": source_event,
        "gh.repo.id": repository_id,
        "gh.repo.archived": payload.is_archived,
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
