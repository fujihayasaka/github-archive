# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/secret_scanning/v1/secret_scanning_feature_toggled_pb"

module SecurityCenter
  class HydroSecretScanningFeatureToggledJob < HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_secret_scanning_feature_toggled

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

      if !SecurityFeatures.visible_features(repository.owner).include?(SecurityFeatures::SECRET_SCANNING)
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:feature_not_available"])
        return
      end

      repository.security_center_notify(
        SecurityFeatures::SECRET_SCANNING,
        source_event:,
      )

      instrument_repository_updated
    end

    sig { override.returns(T::Array[String]) }
    def all_stats_tags
      super.concat([
        "source_event:#{source_event}",
      ]).compact
    end

    sig { override.returns(Integer) }
    def repository_id
      payload.repository_id
    end

    private

    sig { returns(::Hydro::Schemas::Github::SecretScanning::V1::SecretScanningFeatureToggled) }
    memoize def payload
      ::Hydro::Schemas::Github::SecretScanning::V1::SecretScanningFeatureToggled.new(message)
    end

    sig { returns(::Repository) }
    memoize def repository
      ::Repositories::Public.get_active_or_deleted!(repository_id)
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
