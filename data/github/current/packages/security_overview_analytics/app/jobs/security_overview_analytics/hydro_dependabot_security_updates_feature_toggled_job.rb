# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/v1/repository_dependency_updates_vulnerabilities_enabled_pb"
require "hydro/schemas/github/v1/repository_dependency_updates_vulnerabilities_disabled_pb"

module SecurityOverviewAnalytics
  class HydroDependabotSecurityUpdatesFeatureToggledJob < RepositoryHydroMessageJob
    include GitHub::Memoizer

    queue_as :hydro_security_overview_analytics_dependabot_security_updates_feature_toggled

    sig { void }
    def perform
      feature_to_update = :dependabot_security_updates_enabled

      unless TenantValidationHelper.should_handle_feature_enablement_events?(repository.owner)
        GitHub.logger.info(
          "Event skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.feature_status.name": feature_to_update,
          "gh.security_overview_analytics.feature_status.enabled": feature_enabled?,
          "gh.security_overview_analytics.feature_status.reason_to_skip": "Ineligible repository owner."
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.event.dependabot_security_updates_feature_toggled.skipped",
          tags: all_stats_tags + ["reason:ineligible_owner"]
        )
        return
      end

      FeatureStatusRevision.throttle_writes do
        FeatureStatusRevision.upsert_feature_status(
          repository_id:,
          date_id: Date.id_from_time(event_time),
          payload: FeatureStatusRevision::UpdatePayload.new(feature_to_update => feature_enabled?)
        )
      end

      instrument_repository_updated
    end

    protected

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

    sig { override.returns(Integer) }
    memoize def repository_id
      # `repository` is marked nilable in the schema, so safely fallback to 0 for logging
      # Per data warehouse, `repository` is never actually nil for these events.
      payload.repository&.id || 0
    end

    sig { returns(T::Boolean) }
    memoize def feature_enabled?
      return true if payload.is_a? ::Hydro::Schemas::Github::V1::RepositoryDependencyUpdatesVulnerabilitiesEnabled
      false
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.dependabot.security_updates.enabled": feature_enabled?
      })
    end
  end
end
