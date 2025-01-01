# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class HydroCodeScanningFeatureToggledJob < RepositoryHydroMessageJob
    queue_as :hydro_security_overview_analytics_code_scanning_feature_toggled

    sig { void }
    def perform
      feature_to_update = :code_scanning_enabled

      if feature_enabled?
        ::Repository::SecurityCenterBusinessPlanOrgEligibility.new.start_tracking_if_eligible(repository)
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
          "security_overview_analytics.event.code_scanning_feature_toggled.skipped",
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

      if feature_enabled?
        Initialization::Repositories::CodeScanningAlertsJob.perform_later(repository_id:)
        Fanout::Initialization::CodeScanningPullRequestAlertsJob.perform_later(repository_id:, last_session_locked_at: nil)
      end
      instrument_repository_updated
    end

    private

    sig { returns(T::Boolean) }
    memoize def feature_enabled?
      message.dig(:feature_enabled)
    end

    sig { override.returns(String) }
    memoize def source_event
      action = feature_enabled? ? "enabled" : "disabled"
      "#{schema}##{action}"
    end
  end
end
