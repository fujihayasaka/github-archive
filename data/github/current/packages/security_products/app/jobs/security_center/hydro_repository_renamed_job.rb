# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/v1/repository_rename_pb"

module SecurityCenter
  class HydroRepositoryRenamedJob < HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_repository_renamed

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

      config.name = payload.current_name
      RepositorySecurityCenterConfig.throttle_writes { config.save! }

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
      T.must(payload.repository).id
    end

    private

    sig { returns(::Hydro::Schemas::Github::V1::RepositoryRename) }
    memoize def payload
      ::Hydro::Schemas::Github::V1::RepositoryRename.new(message)
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
        "gh.repo.name": payload.current_name,
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
