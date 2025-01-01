# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

module SecurityOverviewAnalytics
  module Reconciliation
    class SecretScanningAlertsDeviationDetectionJob < BatchedJob
      include GitHub::Memoizer
      include FanoutThrottler
      include BatchedJobThrottler

      SecretScanningMetricsAPI = ::GitHub::Proto::SecretScanning::Metrics::V1

      class TokenScanningServiceMetricsApiError < StandardError; end

      queue_as :security_overview_analytics_secret_scanning_alerts_deviation_detection

      retry_on_dirty_exit

      NON_RETRYABLE_EXCEPTIONS = T.let([
        StandardError,
      ], T::Array[T::Class[T.anything]])

      RETRYABLE_EXCEPTIONS = T.let([
        ActiveRecord::RecordNotFound, # replication lag
        TokenScanningServiceMetricsApiError, # paterner service API error
        Freno::Error,
        *Resiliency::Response::UnavailableExceptions, # DB unavailable
      ], T::Array[T.class_of(StandardError)])

      use_replicas ApplicationRecord::SecurityOverviewAnalytics,
        ApplicationRecord::TokenScanningService,
        ApplicationRecord::Repositories,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Configurations

      locked_by timeout: 15.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

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

        next unless job.should_perform?

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

      sig { returns(T.nilable(String)) }
      attr_reader :next_cursor

      sig { override.params(arguments: T.untyped).void }
      def initialize(**arguments)
        @next_cursor = T.let(nil, T.nilable(String))
        # Workaround for https://sorbet.org/docs/error-reference#7019
        super(**T.unsafe(arguments))
      end

      sig do
        override.params(
          args: T.untyped,
          repository_id: Integer,
          offset_item_id: T.any(Integer, [Integer, T.nilable(String)]),
          kwargs: T.untyped,
        )
        .returns(T::Array[SecretScanningMetricsAPI::Alert])
      end
      def next_batch(*args, repository_id:, offset_item_id:, **kwargs)
        encoded_cursor = offset_item_id.last unless offset_item_id.is_a?(Integer)
        next_cursor = Base64.urlsafe_decode64(encoded_cursor) if encoded_cursor.present?
        updated_after = Google::Protobuf::Timestamp.new(seconds: last_session_started_at.to_i) if last_session_started_at.present?
        request = SecretScanningMetricsAPI::GetAlertsForInsightsBackfillRequest.new(
          repo_selector: SecretScanningMetricsAPI::RepoSelector.new(repository_id:),
          include_low_confidence: true,
          updated_after:,
          next_cursor:
        )

        # Pass nil actor since it only used for staging environment check
        response = GitHub::TokenScanning::Service::Client.new(nil).get_alerts_for_insights_backfill(request.to_h)
        response_data = T.let(response.try(:data), T.nilable(SecretScanningMetricsAPI::GetAlertsForInsightsBackfillRequestResponse))

        if response.nil? || response.error || response_data.nil?
          GitHub.logger.error("Error getting secret scanning alerts", {
            "gh.token_scanning_service.error.code": response&.error&.code,
            "gh.token_scanning_service.error.message": response&.error&.msg,
          })
          GitHub.dogstats.increment(
            "security_overview_analytics.reconciliation.error",
            tags: all_stats_tags + ["reason:#{TokenScanningServiceMetricsApiError.name&.underscore}}"]
          )
          raise TokenScanningServiceMetricsApiError
        end

        # Note:
        # By default next_cursor from API is in UTF-8 encoding where ruby will try to convert it to ASCII-8BIT
        # on the way out and fail. To workaround that, we force Base64 encoding so we can decode it later into ASCII-8BIT
        @next_cursor = if response_data.next_cursor.present?
          Base64.urlsafe_encode64(response_data.next_cursor)
        end
        response_data.Alerts.to_a
      end

      sig do
        override.params(
          alerts: T::Array[SecretScanningMetricsAPI::Alert],
          args: T.untyped,
          repository_id: Integer,
          offset_item_id: T.any(Integer, [Integer, T.nilable(String)]),
          kwargs: T.untyped,
        ).void
      end
      def process_batch(alerts, *args, repository_id:, offset_item_id:, **kwargs)
        # Full scan only logic
        if last_session_started_at.nil?
          last_alert_number = offset_item_id.is_a?(Integer) ? offset_item_id : offset_item_id.first

          # On first batch, report deviation as missing_repository if Analytics has no alert data.
          if last_alert_number == 0 && alerts.any? && !SecretScanningAlertRevision.where(repository_id:).exists?
            report_deviation([:missing_repository], alert_numbers: nil)
          end

          # Process orphaned records on full scan. This is necessary and primarily to find out
          # if Analytics missed any purged alerts that can happen when customer choose to do so
          # on removing a custom pattern.
          process_orphaned_alerts(alerts:, last_alert_number:)
        end

        return if alerts.empty?

        # Process alert revisions
        low_confidence_alerts = T.let([], T::Array[SecretScanningMetricsAPI::Alert])
        initial_alert_revisions = T.let({}, T::Hash[Integer, SecretScanningMetricsAPI::Alert])
        current_alert_revisions = T.let({}, T::Hash[Integer, SecretScanningMetricsAPI::Alert])
        alerts_exceeding_retention_limit = Set.new
        alerts.each do |alert|
          next low_confidence_alerts << alert if alert.low_confidence
          if alert.created_at&.to_time == alert.updated_at&.to_time
            initial_alert_revisions[alert.number] = alert
          else
            current_alert_revisions[alert.number] = alert
            alerts_exceeding_retention_limit << alert.number unless Date.within_retention_limit?(alert.updated_at&.to_time)
          end
        end

        initial_alert_revisions.each_pair do |alert_number, alert|
          is_fake_initial_revision = current_alert_revisions.has_key?(alert_number)

          if is_fake_initial_revision && alerts_exceeding_retention_limit.include?(alert_number)
            report_alert_skipped(alert, existing_revision: nil, reason: :exceeds_retention_limit)
            next
          end

          process_alert_revision(alert, is_fake_initial_revision:)
        end

        current_alert_revisions.each_pair do |_, alert|
          process_alert_revision(alert, is_fake_initial_revision: false)
        end

        # Cleanup low confidence alerts
        process_low_confidence_alerts(low_confidence_alerts)
      end

      sig do
        override.params(
          alerts: T::Array[SecretScanningMetricsAPI::Alert],
          kwargs: T.untyped
        ).returns(T::Boolean)
      end
      def has_next_batch?(alerts, **kwargs)
        next_cursor.present?
      end

      sig do
        override.params(
          alerts: T::Array[SecretScanningMetricsAPI::Alert],
          args: T.untyped,
          kwargs: T.untyped
        ).returns([Integer, T.nilable(String)])
      end
      def next_batch_offset_item_id(alerts, *args, **kwargs)
        [alerts.map(&:number).max || 0, next_cursor]
      end

      sig { returns(Reconciliation::Session) }
      memoize def session
        Reconciliation::Session.new(owner_id:, type: Initialization::Type::SecretScanningAlert.serialize)
      end

      sig { returns(T::Boolean) }
      def should_perform?
        unless SecurityCenter::SecurityFeatures.secret_scanning_enabled_for_instance?
          report_reconciliation_skipped("feature_unavailable", reset: true)
          return false
        end

        if repository.deleted?
          report_reconciliation_skipped("repository_deleted", reset: true)
          return false
        end

        owner = repository.owner
        if owner.nil?
          report_reconciliation_skipped("repo_owner_not_found", reset: true)
          return false
        end

        unless TenantValidationHelper.is_owner_in_scope?(owner)
          report_reconciliation_skipped("tenant_not_in_scope", reset: true)
          return false
        end

        unless Initialization.for(owner).initialized?(type: Initialization::Type::SecretScanningAlert)
          report_reconciliation_skipped("tenant_not_initialized", reset: true)
          return false
        end

        true
      end

      sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
      def fanout_jobs
        # If any of the below job queue is being throttled, delay the entire batch.
        [SecretScanningAlertRevisionIngestionJob, SecretScanningAlertsDeletionJob, UpdateFeatureStatusSummaryJob]
      end

      sig { override.params(finished_successfully: T::Boolean, options: T.untyped).returns(T.untyped) }
      def ensure_perform(finished_successfully:, **options)
        return unless finished_successfully

        unless GitHub.enterprise?
          PostReconciliationRepoDeviationCountsJob.perform_with_delay(repository_id:, owner_id:, feature: "secret-scanning")
        end

        # Even if we didn't correct any data, recalculate our rollup anyway
        UpdateFeatureStatusSummaryJob.enqueue(repository_id:)
      end

      protected

      sig { override.returns(T::Array[String]) }
      def stats_tags
        [
          "metric_type:secret_scanning_alerts",
        ].compact
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.repo.id": repository_id,
          "gh.repo.name": repository.name,
          "gh.owner.id": owner_id,
          "gh.security_overview_analytics.job.session_id": session_id,
          "gh.security_overview_analytics.job.last_session_started_at": last_session_started_at,
          "gh.security_overview_analytics.job.session_started_at": session_started_at,
          "gh.security_overview_analytics.job.offset_item_id": arguments.dig(0, :offset_item_id),
          "gh.security_overview_analytics.job.progress": arguments.dig(0, :progress),
          "gh.security_overview_analytics.metric_type": "code_scanning_alerts",
        })
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({
          app: "github-security-center"
        })
      end

      private

      sig { returns(Integer) }
      memoize def repository_id
        T.must(T.let(arguments.dig(0, :repository_id), T.nilable(Integer)))
      end

      sig { returns(::Repository) }
      memoize def repository
        ::Repositories::Public.get_active_or_deleted!(repository_id)
      end

      sig { returns(T.nilable(Time)) }
      memoize def last_session_started_at
        arguments.dig(0, :last_session_started_at)
      end

      sig { returns(Integer) }
      memoize def owner_id
        T.must(repository.owner&.id)
      end

      sig { returns(T.nilable(Time)) }
      memoize def session_started_at
        session.session_started_at
      end

      sig { returns(String) }
      memoize def session_id
        session.id
      end

      sig { returns(String) }
      def source_event
        OrganizationReconciliationJob::RECONCILIATION_EVENT
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
          alerts: T::Array[SecretScanningMetricsAPI::Alert],
          last_alert_number: Integer,
        ).void
      end
      def process_orphaned_alerts(alerts:, last_alert_number:)
        is_last_batch = !has_next_batch?(alerts)

        GitHub.dogstats.distribution_time(
          "security_overview_analytics.secret_scanning_alerts_deviation_detection.orphaned_alerts.dist", tags: all_stats_tags
        ) do
          rel = SecretScanningAlertRevision
            .where(repository_id:)
            .where("alert_number > ?", last_alert_number)

          if alerts.any?
            alert_numbers = alerts.map(&:number).uniq
            rel = rel.where.not(alert_number: alert_numbers)
            rel = rel.where("alert_number <= ?", T.must(alert_numbers.max)) unless is_last_batch
          end

          orphaned_alert_numbers = T.let(rel.pluck(:alert_number), T::Array[Integer])
          orphaned_alert_numbers.each_slice(BATCH_SIZE) do |numbers_in_batch|
            report_deviation([:orphaned_alerts], alert_numbers: numbers_in_batch)
            SecretScanningAlertsDeletionJob.perform_later(repository_id:, alert_numbers: numbers_in_batch)
          end

          GitHub.logger.info(
            "Orphaned alerts processed.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.job.orphaned_alerts_count": orphaned_alert_numbers.size,
            "gh.security_overview_analytics.job.is_last_batch": is_last_batch,
            "gh.security_overview_analytics.job.is_empty_batch": alerts.empty?
          )
        end
      end

      sig do
        params(
          alert: SecretScanningMetricsAPI::Alert,
          is_fake_initial_revision: T::Boolean,
        ).void
      end
      def process_alert_revision(alert, is_fake_initial_revision:)
        # Each alert in the batch can be:
        # - A revision that represents its latest revision since `last_session_started_at`.
        # - A revision that represents the alert's initial state if it was updated.

        date_id = Date.id_from_time(T.must(alert.updated_at).to_time)
        existing_revision = SecretScanningAlertRevision.find_by(
          repository_id:,
          alert_number: alert.number,
          date_id:
        )

        if existing_revision.nil?
          report_alert_revision_deviation([:missing_revision], source: alert, target: existing_revision)
          SecretScanningAlertRevisionIngestionJob.perform_later(
            alert:,
            event_time: Time.current,
            source_event:,
          )
          return
        end

        if existing_revision.alert_updated_at > T.let(alert.updated_at&.to_time&.utc, Time)
          report_alert_skipped(alert, existing_revision:, reason: :old_source_alert_timestamp)
          return
        end

        if is_fake_initial_revision
          report_alert_skipped(alert, existing_revision:, reason: :ignore_fake_initial_revision)
          return
        end

        deviations = existing_revision.fields_with_deviation(alert)
        if deviations.any?
          report_alert_revision_deviation(deviations, source: alert, target: existing_revision)
          SecretScanningAlertRevisionIngestionJob.perform_later(
            alert:,
            event_time: Time.current,
            source_event:,
            force_rewrite: true,
          )
        end
      end

      sig do
        params(
          low_confidence_alerts: T::Array[SecretScanningMetricsAPI::Alert],
        ).void
      end
      def process_low_confidence_alerts(low_confidence_alerts)
        return if low_confidence_alerts.empty?

        alert_numbers = low_confidence_alerts.map(&:number).uniq

        GitHub.dogstats.distribution_time(
          "security_overview_analytics.secret_scanning_alerts_deviation_detection.low_confidence_alerts.dist", tags: all_stats_tags
        ) do
          low_confidence_alert_numbers = T.let(SecretScanningAlertRevision
            .where(repository_id:)
            .where(alert_number: low_confidence_alerts.map(&:number).uniq)
            .pluck(:alert_number).uniq, T::Array[Integer])
          low_confidence_alert_numbers.each_slice(BATCH_SIZE) do |numbers_in_batch|
            report_deviation([:low_confidence_alerts], alert_numbers: numbers_in_batch)
            SecretScanningAlertsDeletionJob.perform_later(repository_id:, alert_numbers: numbers_in_batch)
          end
        end
      end

      sig { params(deviations: T::Array[Symbol], alert_numbers: T.nilable(T::Array[Integer])).void }
      def report_deviation(deviations, alert_numbers:)
        GitHub.logger.info(
          "Deviations found.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.alert_numbers": alert_numbers,
          "gh.security_overview_analytics.job.deviations": deviations
        )
        GitHub.dogstats.count(
          "security_overview_analytics.reconciliation.deviation",
          alert_numbers&.size || 0,
          tags: all_stats_tags + [*deviations.map { |d| "deviation:#{d}" }]
        )
      end

      sig do
        params(
          alert: SecretScanningMetricsAPI::Alert,
          existing_revision: T.nilable(SecretScanningAlertRevision),
          reason: Symbol
        ).void
      end
      def report_alert_skipped(alert, existing_revision:, reason:)
        GitHub.logger.info(
          "Alert skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.source": alert.to_h,
          "gh.security_overview_analytics.job.target": existing_revision&.attributes,
          "gh.security_overview_analytics.job.reason": reason
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.reconciliation.alert_skipped",
          tags: all_stats_tags + ["reason:#{reason}"]
        )
      end

      sig do
        params(
          deviations: T::Array[Symbol],
          source: SecretScanningMetricsAPI::Alert,
          target: T.nilable(SecretScanningAlertRevision)
        ).void
      end
      def report_alert_revision_deviation(deviations, source:, target:)
        GitHub.logger.info(
          "Deviations found.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.source": source.to_h,
          "gh.security_overview_analytics.job.target": target&.attributes,
          "gh.security_overview_analytics.job.deviations": deviations
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.reconciliation.deviation",
          tags: all_stats_tags + [*deviations.map { |d| "deviation:#{d}" }]
        )
      end
    end
  end
end
