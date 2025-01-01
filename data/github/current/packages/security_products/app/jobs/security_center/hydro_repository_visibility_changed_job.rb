# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/repositories/v1/visibility_changed_pb"

module SecurityCenter
  class HydroRepositoryVisibilityChangedJob < HydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_repository_visibility_changed

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

      config.visibility = payload.new_visibility.to_s.downcase
      RepositorySecurityCenterConfig.throttle_writes { config.save! }

      GitHub.logger.info("Notifying security features", "code.namespace": self.class.name, "code.function": __method__,)
      # Keeping legacy (non-hydro) event name for compatibility
      # Legacy payload is used to short circuit whether to publish event for non-GHAS, no-longer-public repositories.
      pubsub_payload = { previous_visibility: payload.old_visibility.to_s.downcase }
      SecurityCenterUpdater.notify_security_features_for_repo(repository, source_event: "repo.access", payload: pubsub_payload)

      instrument_repository_updated
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

    sig { returns(::Hydro::Schemas::Github::Repositories::V1::VisibilityChanged) }
    memoize def payload
      ::Hydro::Schemas::Github::Repositories::V1::VisibilityChanged.new(message)
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
        "gh.repo.visibility": payload.new_visibility,
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
