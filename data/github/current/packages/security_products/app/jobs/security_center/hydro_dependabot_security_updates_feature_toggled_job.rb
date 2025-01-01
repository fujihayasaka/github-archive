# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/v1/repository_dependency_updates_vulnerabilities_enabled_pb"
require "hydro/schemas/github/v1/repository_dependency_updates_vulnerabilities_disabled_pb"

module SecurityCenter
  class HydroDependabotSecurityUpdatesFeatureToggledJob < HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    queue_as :hydro_security_center_dependabot_security_updates_feature_toggled

    retry_on_dirty_exit

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

      if !SecurityFeatures.visible_features(repository.owner).include?(SecurityFeatures::DEPENDABOT_ALERTS)
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:feature_not_available"])
        return
      end

      repository.security_center_notify(
        :dependabot_security_updates,
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
      T.must(payload.repository).id
    end

    private

    sig do
      returns(T.any(
        ::Hydro::Schemas::Github::V1::RepositoryDependencyUpdatesVulnerabilitiesEnabled,
        ::Hydro::Schemas::Github::V1::RepositoryDependencyUpdatesVulnerabilitiesDisabled,
      ))
    end
    memoize def payload
      case schema
      when /github\.v1\.RepositoryDependencyUpdatesVulnerabilitiesEnabled\Z/
        ::Hydro::Schemas::Github::V1::RepositoryDependencyUpdatesVulnerabilitiesEnabled.new(message)
      when /github\.v1\.RepositoryDependencyUpdatesVulnerabilitiesDisabled\Z/
        ::Hydro::Schemas::Github::V1::RepositoryDependencyUpdatesVulnerabilitiesDisabled.new(message)
      else
        raise "Unsupported schema: #{schema}"
      end
    end

    sig { returns(::Repository) }
    memoize def repository
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { returns(String) }
    memoize def source_event
      schema
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
