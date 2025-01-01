# typed: strict
# frozen_string_literal: true

require "hydro/schemas/code_scanning/v0/code_scanning_feature_toggled_pb"
require "hydro/schemas/github/code_security/v1/code_security_feature_toggled_pb"

module SecurityCenter
  class HydroCodeScanningFeatureToggledJob < HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_code_scanning_feature_toggled

    retry_on_dirty_exit
    retry_on CodeScanning::AutoCodeqlError

    sig { void }
    def perform
      if repository.deleted?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:repo_deleted"])
        return
      end

      if repository.owner.nil?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_found"])
        return
      end

      if !repository.owner&.organization?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_org"])
        return
      end

      if !SecurityFeatures.visible_features(repository.owner).include?(SecurityFeatures::CODE_SCANNING)
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:feature_not_available"])
        return
      end

      repository.security_center_notify(
        SecurityFeatures::CODE_SCANNING,
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

    sig { returns(T.any(::Hydro::Schemas::CodeScanning::V0::CodeScanningFeatureToggled, ::Hydro::Schemas::Github::CodeSecurity::V1::CodeSecurityFeatureToggled)) }
    memoize def payload
      if schema == "github.code_security.v1.CodeSecurityFeatureToggled"
        return ::Hydro::Schemas::Github::CodeSecurity::V1::CodeSecurityFeatureToggled.new(message)
      end

      ::Hydro::Schemas::CodeScanning::V0::CodeScanningFeatureToggled.new(message)
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
