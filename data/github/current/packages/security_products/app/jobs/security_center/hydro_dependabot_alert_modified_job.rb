# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityCenter
  class HydroDependabotAlertModifiedJob < HydroMessageJob
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    SUPPORTED_ACTIONS = T.let(%w[
      create
      resolve
      dismiss
      reopen
      reintroduce
      auto_dismiss
      auto_reopen
      withdraw
      severity_change
    ].freeze, T::Array[String])

    class RepositoryNotFound < ActiveRecord::RecordNotFound

      sig { params(id: Integer).void }
      def initialize(id)
        error = "Couldn't find #{::Repository.name} with #{::Repository.primary_key}=#{id}"
        super(error, ::Repository.name, ::Repository.primary_key, id)
      end
    end

    queue_as :hydro_security_center_dependabot_alert_modified

    retry_on_dirty_exit

    sig { void }
    def perform
      if !SUPPORTED_ACTIONS.include?(payload.action)
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:action_not_supported"])
        GitHub.logger.info("Unsupported event; skipping event", "code.namespace": self.class.name, "code.function": __method__)
        return
      end

      RepositorySyncJob.enqueue_once_per_interval(
        kwargs: {
          repository_id:,
          source_event:,
          feature_type:,
          event_timestamp: timestamp,
        },
        interval: 60, # in seconds
        run_at_beginning_of_interval: false,
        unique_id: RepositorySyncJob.restraint_lock_key(repository_id:, feature_type:),
      )
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

    sig { returns(::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent) }
    memoize def payload
      ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent.new(message)
    end

    sig { returns(T.nilable(::Repository)) }
    memoize def repository
      ::Repositories::Public.get_active_or_deleted(repository_id)
    end

    sig { returns(String) }
    def feature_type
      SecurityFeatures::DEPENDABOT_ALERTS
    end

    sig { returns(String) }
    memoize def source_event
      # Because all changes to a Dependabot alert use the same event, we need some way to distinguish for telemetry.
      action = message.dig(:action)
      "#{schema}##{action}"
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.source_event": source_event,
        "gh.repo.id": repository_id,
        "gh.security_alerts.id": message.dig(:repository_vulnerability_alert_id),
        "gh.security_alerts.vulnerability.id": message.dig(:vulnerability_id),
        "gh.security_alerts.vulnerable_version_range.id": message.dig(:vulnerable_version_range_id),
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
