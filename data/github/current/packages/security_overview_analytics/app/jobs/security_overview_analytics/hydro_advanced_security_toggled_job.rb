# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_center/v0/advanced_security_toggled_pb"

module SecurityOverviewAnalytics
  class HydroAdvancedSecurityToggledJob < RepositoryHydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include LifecycleEventHandler::Hydro

    queue_as :hydro_security_overview_analytics_advanced_security_toggled

    sig { void }
    def perform
      feature_to_update = :advanced_security_enabled

      unless TenantValidationHelper.should_handle_feature_enablement_events?(repository.owner)
        GitHub.logger.info(
          "Event skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.feature_status.name": feature_to_update,
          "gh.security_overview_analytics.feature_status.enabled": payload.feature_enabled,
          "gh.security_overview_analytics.feature_status.reason_to_skip": "Ineligible repository owner."
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.event.advanced_security_feature_toggled.skipped",
          tags: all_stats_tags + ["reason:ineligible_owner"]
        )
        return
      end

      instrument_incremental_deviation(feature_to_update, payload.feature_enabled, repository_id) do
        repository.security_feature_configured?(:ADVANCED_SECURITY)
      end

      date_id = Date.id_from_date(event_time.utc.to_date)

      FeatureStatusRevision.throttle_writes do
        FeatureStatusRevision.upsert_feature_status(
          repository_id:,
          date_id:,
          payload: FeatureStatusRevision::UpdatePayload.new(feature_to_update => payload.feature_enabled)
        )
      end

      instrument_repository_updated
    end

    protected

    sig { returns(::Hydro::Schemas::Github::SecurityCenter::V0::AdvancedSecurityToggled) }
    memoize def payload
      ::Hydro::Schemas::Github::SecurityCenter::V0::AdvancedSecurityToggled.new(message)
    end

    sig { override.returns(String) }
    memoize def source_event
      action = payload.feature_enabled ? "enabled" : "disabled"
      "#{schema}##{action}"
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.advanced_security.enabled": payload.feature_enabled
      })
    end
  end
end
