# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alerts_analytics_event_pb"

module SecurityOverviewAnalytics
  class HydroDependabotAlertsFeatureToggledJob < RepositoryHydroMessageJob
    extend T::Sig
    include GitHub::Memoizer

    SUPPORTED_ACTIONS = T.let(%w[enable disable].freeze, T::Array[String])

    queue_as :hydro_security_overview_analytics_dependabot_alerts_feature_toggled

    sig { void }
    def perform
      feature_to_update = :dependabot_alerts_enabled

      unless SUPPORTED_ACTIONS.include?(payload.action)
        GitHub.logger.info(
          "Event skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.feature_status.name": feature_to_update,
          "gh.security_overview_analytics.feature_status.enabled": feature_enabled?,
          "gh.security_overview_analytics.feature_status.reason_to_skip": "Unsupported event."
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.event.dependabot_alerts_feature_toggled.skipped",
          tags: all_stats_tags + ["reason:unsupported_event"]
        )
        return
      end

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
          "security_overview_analytics.event.dependabot_alerts_feature_toggled.skipped",
          tags: all_stats_tags + ["reason:ineligible_owner"]
        )
        return
      end

      instrument_incremental_deviation(feature_to_update, feature_enabled?, repository_id) do
        repository.security_feature_configured?(:DEPENDABOT_ALERTS)
      end

      date_id = Date.id_from_date(event_time.utc.to_date)

      FeatureStatusRevision.throttle_writes do
        FeatureStatusRevision.upsert_feature_status(
          repository_id:,
          date_id:,
          payload: FeatureStatusRevision::UpdatePayload.new(feature_to_update => feature_enabled?)
        )
      end

      Initialization::Repositories::DependabotAlertsJob.perform_later(repository_id:) if feature_enabled?

      instrument_repository_updated
    end

    protected

    sig { returns(::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertsAnalyticsEvent) }
    memoize def payload
      ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertsAnalyticsEvent.new(message)
    end

    sig { override.returns(String) }
    memoize def source_event
      "#{schema}##{payload.action}"
    end

    sig { override.returns(Integer) }
    memoize def repository_id
      # `repository_id`` is only guaranteed on SUPPORTED_ACTIONS
      # Safely fallback to 0 for actions that we do not support for logging context.
      payload.repository_id&.value || 0
    end

    sig { returns(T::Boolean) }
    memoize def feature_enabled?
      payload.action == "enable" ? true : false
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.dependabot_alerts.enabled": feature_enabled?
      })
    end
  end
end
