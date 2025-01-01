# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class DependabotAlertsJob < BaseBatchedJob
        include GitHub::Memoizer
        include FanoutThrottler
        include BatchedJobThrottler

        queue_as :security_overview_analytics_repository_dependabot_alerts_initialization

        use_replicas \
          ApplicationRecord::Configurations,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Notify,
          ApplicationRecord::Repositories,
          ApplicationRecord::SecurityOverviewAnalytics,
          allow_replication_lag: []

        locked_by timeout: 15.minutes, key: ->(job) do
          repository_id = job.arguments.dig(0, :repository_id)
          DEFAULT_LOCK_STRINGIFY_PROC.call([repository_id])
        end

        RepositoryVulnerabilityAlertEvent = ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent
        EventState = RepositoryVulnerabilityAlertEvent::State
        LastStateChangeReason = RepositoryVulnerabilityAlertEvent::LastStateChangeReason

        sig do
          override.params(
            args: T.untyped,
            repository_id: Integer,
            offset_item_id: Integer,
            kwargs: T.untyped,
          )
          .returns(T::Array[RepositoryVulnerabilityAlert])
        end
        def next_batch(*args, repository_id:, offset_item_id:, **kwargs)
          RepositoryVulnerabilityAlert
            .where(repository_id: repository_id)
            .where("id > ?", offset_item_id)
            .order(:id)
            .limit(BATCH_SIZE)
            # preloads the associations needed to fetch metadata for the alert
            .includes(:vulnerable_version_range, :vulnerability)
            .to_a
        end

        sig do
          override.params(
            alerts: T::Array[RepositoryVulnerabilityAlert],
            args: T.untyped,
            repository_id: Integer,
            kwargs: T.untyped,
          )
          .void
        end
        def process_batch(alerts, *args, repository_id:, **kwargs)
          alerts.each do |alert|
            created_time = alert.created_at&.utc
            updated_time = alert.updated_at&.utc

            # When alert's recent timestamp is within retention limit and it was updated after its creation date,
            # we use created_at as event_time to create an "initial" revision
            if Date.within_retention_limit?(updated_time) && created_time.to_date != updated_time.to_date
              queue_upsert_job(alert, is_initial_event: true, event_time: created_time)
            end

            # Use updated_at as event_time to create "latest" revision
            queue_upsert_job(alert, is_initial_event: false, event_time: updated_time)
          end

          alert_ids = alerts.map(&:id)

          GitHub.logger.info(
            "Batch completed",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.initialization_job.alert_ids": alert_ids,
          )
        end

        sig { params(alert: RepositoryVulnerabilityAlert, is_initial_event: T::Boolean, event_time: Time).void }
        def queue_upsert_job(alert, is_initial_event:, event_time:)
          # Convert alert object to event payload
          event_payload = DependabotAlertRevision.create_event_payload(alert:, is_initial_event:)
          date_id = Date.id_from_time(event_payload.updated_at&.to_time)

          # Don't enqueue if alert revisions already exist for the repository for this particular day
          if SecurityOverviewAnalytics::DependabotAlertRevision.where(alert_number: alert.number, repository_id:, date_id:).exists?
            GitHub.logger.info("DependabotAlertRevisions already exist for this alert in repository")
            GitHub.dogstats.increment(
              "security_overview_analytics.dependabot_alert_revision_ingestion.skipped",
              tags: all_stats_tags + ["reason:revisions_already_exist"]
            )
            return
          end

          DependabotAlertRevisionIngestionJob.perform_later(
            alert: event_payload,
            event_time:,
            source_event: TenantBaseJob::INITIALIZATION_EVENT,
          )
        end

        sig { override.params(args: T.untyped, options: T.untyped).void }
        def finalize_batch(*args, **options)
          clear_lock
        end

        sig { override.returns(T::Boolean) }
        def should_initialize?
          unless SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
            instrument_repository_skipped(:feature_unavailable)
            return false
          end

          if repository.deleted?
            instrument_repository_skipped(:repository_deleted)
            return false
          end

          unless repository.owner&.organization?
            instrument_repository_skipped(:not_org_owned_repo)
            return false
          end

          owner = T.must(repository.owner)
          unless TenantValidationHelper.is_owner_in_scope?(owner)
            instrument_repository_skipped(:tenant_not_in_scope)
            return false
          end

          true
        end

        sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
        def fanout_jobs
          # If any of the below job queue is being throttled, delay the entire batch.
          [DependabotAlertRevisionIngestionJob]
        end

        private

        sig { params(reason: Symbol).void }
        def instrument_repository_skipped(reason)
          GitHub.logger.info(
            "Initialization skipped.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.job.reason": reason,
          )
          GitHub.dogstats.increment(
            "security_overview_analytics.initialization.repository_dependabot_alerts.skipped",
            tags: all_stats_tags + ["reason:#{reason}"]
          )
        end
      end
    end
  end
end
