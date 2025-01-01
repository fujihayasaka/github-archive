# typed: strict
# frozen_string_literal: true

require "hydro/schemas/github/security_alerts/v1/repository_vulnerability_alert_lifecycle_event_pb"

module SecurityOverviewAnalytics
  module Reconciliation
    class DependabotAlertsDeviationDetectionJob < BatchedJob
      include GitHub::Memoizer
      include FanoutThrottler
      include BatchedJobThrottler

      queue_as :security_overview_analytics_dependabot_alerts_reconciliation

      retry_on_dirty_exit

      use_replicas ApplicationRecord::SecurityOverviewAnalytics,
        ApplicationRecord::Repositories,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Configurations,
        allow_replication_lag: [
          ApplicationRecord::Notify
        ]

      locked_by timeout: 15.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

      RepositoryVulnerabilityAlertEvent = ::Hydro::Schemas::Github::SecurityAlerts::V1::RepositoryVulnerabilityAlertLifecycleEvent
      EventState = RepositoryVulnerabilityAlertEvent::State
      LastStateChangeReason = RepositoryVulnerabilityAlertEvent::LastStateChangeReason

      NON_RETRYABLE_EXCEPTIONS = T.let([
        StandardError,
      ], T::Array[T::Class[T.anything]])

      RETRYABLE_EXCEPTIONS = T.let([
        Freno::Error,
        *Resiliency::Response::UnavailableExceptions, # DB unavailable
      ], T::Array[T::Class[T.anything]])

      # Custom retry for recoverable exceptions. Reset session lock if attempts are exhausted.
      RETRYABLE_EXCEPTIONS.each do |error_class|
        retry_on error_class, wait: :polynomially_longer, attempts: 5 do |job, error|
          last_session_started_at = job.arguments.first&.dig(:last_session_started_at)
          job.session.reset!(last_session_started_at:)

          GitHub.dogstats.increment("security_overview_analytics.reconciliation.abort",
            tags: job.all_stats_tags + [
              "reason:stopped_retry",
              "error:#{error.class.name.underscore}"
            ]
          )
        end
      end

      around_enqueue do |job, block|
        repository_id = job.arguments.dig(0, :repository_id)
        if repository_id.blank?
          clear_lock
          raise ArgumentError.new("Missing repository_id.")
        end

        block.call
      end

      around_perform do |job, block|
        if !session.locked?
          # This means the session has been reset and should no longer continue.
          report_reconciliation_skipped("session_reset")
          next
        end

        unless SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
          report_reconciliation_skipped("feature_unavailable", reset: true)
          next
        end

        if repository.deleted?
          report_reconciliation_skipped("repository_deleted", reset: true)
          next
        end

        owner = repository.owner
        unless owner&.organization?
          report_reconciliation_skipped("owner_not_an_org", reset: true)
          next
        end

        unless TenantValidationHelper.is_owner_in_scope?(owner)
          report_reconciliation_skipped("owner_not_in_scope", reset: true)
          next
        end

        unless Initialization.for(owner).initialized?(type: Initialization::Type::DependabotAlerts)
          report_reconciliation_skipped("tenant_not_initialized", reset: true)
          next
        end

        # Proceed with the batch
        block.call

      rescue *RETRYABLE_EXCEPTIONS
        raise
      rescue *NON_RETRYABLE_EXCEPTIONS => e
        # Reset session and report error
        session.reset!(last_session_started_at:)
        GitHub.dogstats.increment("security_overview_analytics.reconciliation.abort",
          tags: job.all_stats_tags + [
            "reason:stopped_retry",
            "error:#{e.class.name&.underscore}"
          ]
        )

        raise
      end

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
        # Scope to all alerts because withdrawn alerts still persist in RVA,
        # and the state in our revisions may have deviated from the source.
        RepositoryVulnerabilityAlert.active_and_inactive
          .where(repository_id: repository_id)
          .where("id > ?", offset_item_id)
          # Use the last_session_started_at to only include the alerts that were updated since the last reconciliation.
          # If last_session_started_at is nil, we'll reconcile everything since this is the first reconciliation run.
          .then { |rel| last_session_started_at.present? ? rel.where("updated_at > ?", last_session_started_at) : rel }
          .order(:id)
          .limit(BATCH_SIZE)
          .to_a
      end

      sig do
        override.params(
          alerts: T::Array[RepositoryVulnerabilityAlert],
          args: T.untyped,
          offset_item_id: Integer,
          kwargs: T.untyped,
        ).void
      end
      def process_batch(alerts, *args, offset_item_id:, **kwargs)
        # Types of alerts deviations we're handling with reconciliation
        # 1. Missing alert revisions: alerts exist in RVA but no revisions in SOA
        # 2. Deviations: exist in both, but SOA revisions deviate from RVA alerts
        #
        # There is a third type that we're NOT handling here
        # 3. Orphaned alerts: not in RVA but have revisions in SOA - these revisions will be purged by a separate job
        alerts.each do |alert|
          created_time = alert.created_at&.utc
          updated_time = alert.updated_at&.utc

          # For withdrawn alerts, skip or purge them if they have revisions in SOA.
          if alert.withdrawn?
            handle_withdrawn_alert(alert_id: alert.id, alert_number: alert.number)
            next
          end

          latest_revision = DependabotAlertRevision
            .where(
              repository_id:,
              alert_number: alert.number,
              next_revision_date_id: Date::FUTURE_DATE_ID
            ).first

          # Here, we are trying to reconstruct the initial revision and also the most recent one
          # at the times the events happened, not at the _current_ time when reconciliation runs.
          # This is achieved through the use of the alert's created_at or updated_at as the revision event_time.

          # Handle missing alert
          if latest_revision.nil?
            report_deviation_and_queue_remediation(
              deviations: [:missing_alert],
              alert:,
              is_initial_event: false
            )

            # When alert's recent timestamp is within retention limit and it was updated after its creation date,
            # we may have missed both the initial alert creation event and subsequent update events after.
            # If this is the case, upsert the initial revision too.
            if Date.within_retention_limit?(updated_time) && updated_time > created_time
              report_deviation_and_queue_remediation(
                deviations: [:missing_alert, :missing_initial_revision],
                alert:,
                is_initial_event: true
              )
            end

            next
          end

          # Handle missing initial revision for existing alert.
          # This could happen when we missed the initial creation event, but captured the subsequent update events.
          initial_revision = DependabotAlertRevision
            .where(
              repository_id:,
              alert_number: alert.number,
              date_id: ::SecurityOverviewAnalytics::Date.id_from_time(created_time)
            ).first

          if initial_revision.nil?
            # Queue remediation to upsert initial revision
            report_deviation_and_queue_remediation(
              deviations: [:missing_initial_revision],
              alert:,
              is_initial_event: true
            )
          end

          # Handle deviations for latest revision
          deviations = latest_revision.fields_with_deviation(alert:)
          next unless deviations.any?

          report_deviation_and_queue_remediation(
            deviations:,
            alert:,
            is_initial_event: false,
            force_rewrite: true
          )
        end
      end

      sig { override.params(finished_successfully: T::Boolean, options: T.untyped).returns(T.untyped) }
      def ensure_perform(finished_successfully:, **options)
        return unless finished_successfully

        unless GitHub.enterprise?
          PostReconciliationRepoDeviationCountsJob.perform_with_delay(repository_id:, owner_id:, feature: "dependabot")
        end

        # Even if we didn't correct any data, recalculate our rollup anyway
        UpdateFeatureStatusSummaryJob.enqueue(repository_id:)
      end

      sig { returns(Reconciliation::Session) }
      memoize def session
        Reconciliation::Session.new(owner_id:, type: Initialization::Type::DependabotAlerts.serialize)
      end

      sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
      def fanout_jobs
        [DependabotAlertRevisionIngestionJob, UpdateFeatureStatusSummaryJob]
      end

      protected

      sig { override.returns(T::Array[String]) }
      def stats_tags
        [
          "metric_type:dependabot_alerts",
        ].compact
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.repo.id": repository_id,
          "gh.repo.name": repository.name,
          "gh.owner.id": owner_id,
          "gh.security_overview_analytics.job.session_id": session_id,
          "gh.security_overview_analytics.job.session_started_at": session_started_at,
          "gh.security_overview_analytics.job.last_session_started_at": last_session_started_at,
          "gh.security_overview_analytics.job.offset_item_id": arguments.dig(0, :offset_item_id),
          "gh.security_overview_analytics.job.progress": arguments.dig(0, :progress),
          "gh.security_overview_analytics.metric_type": "dependabot_alerts",
        })
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({
          app: "github-security-center"
        })
      end

      private

      sig { params(alert_id: Integer, alert_number: Integer).void }
      def handle_withdrawn_alert(alert_id:, alert_number:)
        if DependabotAlertRevision.where(repository_id:, alert_number:).exists?
          # If revisions still exist for this alert, that means we missed the withdrawal event.
          # Delete all revisions of this alert.
          DependabotAlertRevision.throttle_writes_with_retry do
            DependabotAlertRevision.where(repository_id:, alert_number:).delete_all
          end

          report_deviation(alert_id:, alert_number:, deviations: [:alert_withdrawn])
        end
      end

      sig { returns(Integer) }
      memoize def repository_id
        (arguments[0] || {}).fetch(:repository_id)
      end

      sig { returns(::Repository) }
      memoize def repository
        ::Repositories::Public.get_active_or_deleted!(repository_id)
      end

      sig { returns(Integer) }
      memoize def owner_id
        repository.owner&.id
      end

      sig { returns(String) }
      memoize def session_id
        session.id
      end

      sig { returns(T.nilable(Time)) }
      memoize def last_session_started_at
        (arguments[0] || {}).fetch(:last_session_started_at, nil)
      end

      sig { returns(T.nilable(Time)) }
      memoize def session_started_at
        session.session_started_at
      end

      sig { params(reason: String, reset: T::Boolean).void }
      def report_reconciliation_skipped(reason, reset: false)
        # If required, reset session lock to the previous session run
        session.reset!(last_session_started_at:) if reset

        GitHub.logger.info(
          "Reconciliation skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": reason,
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.reconciliation.skipped",
          tags: all_stats_tags + [
            "reason:#{reason.parameterize.underscore}"
          ]
        )
      end

      sig do
        params(
          alert_id: Integer,
          alert_number: Integer,
          deviations: T::Array[Symbol]
        ).void
      end
      def report_deviation(alert_id:, alert_number:, deviations:)
        GitHub.logger.info(
          "Deviation found.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.dependabot.alert_id": alert_id,
          "gh.security_overview_analytics.dependabot.alert_number": alert_number,
          "gh.security_overview_analytics.deviations": deviations
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.reconciliation.deviation",
          tags: all_stats_tags + [*deviations.map { |d| "deviation:#{d}" }]
        )
      end

      sig do
        params(
          deviations: T::Array[Symbol],
          alert: RepositoryVulnerabilityAlert,
          is_initial_event: T::Boolean,
          force_rewrite: T::Boolean
        ).void
      end
      def report_deviation_and_queue_remediation(deviations:, alert:, is_initial_event:, force_rewrite: false)
        report_deviation(
          alert_id: alert.id,
          alert_number: alert.number,
          deviations:
        )

        update_severity = deviations.include?(:alert_severity)
        event_payload = DependabotAlertRevision.create_event_payload(alert:, is_initial_event:)
        event_time = event_payload.updated_at&.to_time
        DependabotAlertRevisionIngestionJob.perform_later(
          alert: event_payload,
          event_time: event_time,
          source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT,
          force_rewrite:,
          update_severity:,
        )
      end
    end
  end
end
