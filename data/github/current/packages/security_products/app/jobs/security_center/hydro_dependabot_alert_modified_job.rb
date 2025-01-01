# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityCenter
  class HydroDependabotAlertModifiedJob < HydroMessageJob
    extend T::Sig
    include GitHub::Memoizer
    include LifecycleEventHandler
    include RepositoryHydroMessageJobTenantContext

    class RepositoryNotFound < ActiveRecord::RecordNotFound
      extend T::Sig

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
      if FlipperActorAdapters::Repository.new(repository_id).feature_enabled?(:security_center_dependabot_alerts_enqueue_repo_sync)
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
        return
      end

      repo = repository
      if repo.nil?
        if payload.action == "resolve" && !RepositoryVulnerabilityAlert.exists?(payload.repository_vulnerability_alert_id)
          # On repository hard-deletion, Dependabot alerts emit an alert resolution event - triggering security center updates.
          # This is the "terminal" resolution event; both the repository and alert have been purged.
          # We should not update in this scenario.
          GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:repo_not_found"])
          return
        elsif payload.action == "withdraw"
          # On withdraw, when a repository is not found, its likely cleaning up orphaned data.
          # Enqueue RepositorySyncJob to properly clean up repository data from all tables.
          RepositorySyncJob.perform_later(
            repository_id:,
            source_event:,
            feature_type:,
            event_timestamp: timestamp,
          )
          return
        end

        # Otherwise, assume this is replication lag and let the job retry.
        raise RepositoryNotFound.new(repository_id)
      end

      if repo.deleted?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:repo_deleted"])
        return
      end

      if repo.owner.nil?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_found"])
        return
      end

      if !repo.owner&.organization?
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:owner_not_org"])
        return
      end

      if !SecurityFeatures.visible_features(repo.owner).include?(feature_type)
        GitHub.dogstats.increment("security_center.repository_update.abort", tags: all_stats_tags + ["cause:feature_not_available"])
        return
      end

      repo.security_center_notify(
        feature_type,
        source_event:,
        skip_subfeature_updates: true,
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
