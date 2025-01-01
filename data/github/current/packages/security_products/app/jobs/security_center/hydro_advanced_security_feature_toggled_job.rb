# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_center/v0/advanced_security_toggled_pb"

module SecurityCenter
  class HydroAdvancedSecurityFeatureToggledJob < HydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_advanced_security_feature_toggled

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

      check_and_update_business(config)

      config.ghas_enabled = payload.feature_enabled
      RepositorySecurityCenterConfig.throttle_writes { config.save! }

      if owner.organization?
        GitHub.logger.info("Notifying security features", "code.namespace": self.class.name, "code.function": __method__)
        SecurityCenterUpdater.notify_security_features_for_repo(repository, source_event:)
      end

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

    sig { params(config: RepositorySecurityCenterConfig).void }
    def check_and_update_business(config)
      business_id = repository.business_id

      # A change in business ID may indicate this job is queued from a Org Transfer
      if config.business_id != business_id
        config.business_id = business_id
      end
    end

    sig { returns(::Hydro::Schemas::Github::SecurityCenter::V0::AdvancedSecurityToggled) }
    memoize def payload
      ::Hydro::Schemas::Github::SecurityCenter::V0::AdvancedSecurityToggled.new(message)
    end

    sig { returns(::Repository) }
    memoize def repository
      Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { returns(String) }
    memoize def source_event
      # Because the same topic/schema is used for both enable/disable, we need some way to distinguish for telemetry.
      action = payload.feature_enabled ? "enable" : "disable"
      "#{schema}##{action}"
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.source_event": source_event,
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
