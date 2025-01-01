# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alerts_analytics_event_pb"

module SecurityCenter
  class HydroDependabotFeatureToggledJob < HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    class UnsupportedActionError < StandardError; end

    SUPPORTED_ACTIONS = T.let(%w[enable disable].freeze, T::Array[String])

    queue_as :hydro_security_center_dependabot_feature_toggled

    retry_on_dirty_exit

    sig { void }
    def perform
      # The topic is used for other notifications about the Dependabot alerts feature.
      # Be explicit about what actions we support.
      unless SUPPORTED_ACTIONS.include?(payload.action)
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:action_not_supported"])
        return
      end

      if repository&.deleted?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:repo_deleted"])
        return
      end

      if repository&.owner.nil?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_found"])
        return
      end

      if !repository&.owner&.organization?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_org"])
        return
      end

      if !SecurityFeatures.visible_features(repository&.owner).include?(SecurityFeatures::DEPENDABOT_ALERTS)
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:feature_not_available"])
        return
      end

      repository&.security_center_notify(
        SecurityFeatures::DEPENDABOT_ALERTS,
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
      payload.repository_id&.value || 0
    end

    private

    sig { returns(::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertsAnalyticsEvent) }
    memoize def payload
      ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertsAnalyticsEvent.new(message)
    end

    sig { returns(T.nilable(::Repository)) }
    memoize def repository
      return nil if repository_id.zero?
      ::Repositories::Public.get_active_or_deleted!(repository_id)
    end

    sig { returns(String) }
    memoize def source_event
      # Because the same topic/schema is used for multiple actions, we need some way to distinguish for telemetry.
      action = message.dig(:action)
      "#{schema}##{action}"
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.source_event": source_event,
        "gh.repo.id": payload.repository_id&.value,
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
