# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Reconciliation
    class CodeScanningAlertsDeviationDetectionJob < BatchedJob
      include GitHub::Memoizer
      include FanoutThrottler
      include BatchedJobThrottler

      TurboscanInsightsAlert = ::Turboscan::Proto::InsightsAlert
      TELEMETRY_BATCH_SIZE = 25

      queue_as :security_overview_analytics_code_scanning_alerts_reconciliation

      use_replicas \
        ::ApplicationRecord::Configurations,
        ::ApplicationRecord::Mysql1,
        ::ApplicationRecord::Mysql5,
        ::ApplicationRecord::Repositories,
        ::ApplicationRecord::SecurityOverviewAnalytics

      class TurboscanError < StandardError; end

      retry_on_dirty_exit

      # The base BatchedJob adds several parameters that effectively make every enqueue unique.
      # Limit this to only the input parameters. Requires manually clearing the lock in finalize_batch.
      locked_by timeout: 15.minutes, key: ->(job) do
        repository_id = job.arguments.dig(0, :repository_id)
        DEFAULT_LOCK_STRINGIFY_PROC.call([repository_id])
      end

      NON_RETRYABLE_EXCEPTIONS = T.let([
        StandardError,
      ], T::Array[T::Class[T.anything]])

      RETRYABLE_EXCEPTIONS = T.let([
        TurboscanError,
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
        if job.arguments.dig(0, :repository_id).blank?
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

        unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
          report_reconciliation_skipped("feature_unavailable", reset: true)
          next
        end

        owner = repository.owner
        unless owner&.organization?
          report_reconciliation_skipped("owner_not_org", reset: true)
          next
        end

        unless TenantValidationHelper.is_owner_in_scope?(owner)
          report_reconciliation_skipped("owner_not_in_scope", reset: true)
          next
        end

        unless Initialization.for(owner).initialized?(type: Initialization::Type::CodeScanningAlert)
          report_reconciliation_skipped("tenant_not_initialized", reset: true)
          next
        end

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
        super(**arguments)

        @next_cursor = T.let(nil, T.nilable(String))
      end

      sig do
        override.params(
          args: T.untyped,
          repository_id: Integer,
          offset_item_id: T.any(Integer, [Integer, T.nilable(String)]),
          kwargs: T.untyped,
        )
        .returns(T::Array[TurboscanInsightsAlert])
      end
      def next_batch(*args, repository_id:, offset_item_id:, **kwargs)
        next_cursor = offset_item_id.is_a?(Array) ? offset_item_id.last : nil
        updated_after = Google::Protobuf::Timestamp.new(seconds: last_session_started_at.to_i) if last_session_started_at.present?
        req = ::Turboscan::Proto::GetAlertsForInsightsBackfillRequest.new(
          repository_id:,
          updated_after:,
          next_cursor:,
        )
        res = ::GitHub::Turboscan::Insights.get_alerts_for_insights_backfill(req.to_h)
        res_data = T.let(res.try(:data), T.nilable(Turboscan::Proto::GetAlertsForInsightsBackfillRequestResponse))

        if res.nil? || res.error.present? || res_data.nil?
          GitHub.logger.error("Error getting Turboscan alerts", {
            "gh.turboscan.error.code": res&.error&.code,
            "gh.turboscan.error.message": res&.error&.msg,
          })
          GitHub.dogstats.increment(
            "security_overview_analytics.reconciliation.error",
            tags: all_stats_tags + ["cause:turboscan_error"]
          )
          raise TurboscanError
        end

        @next_cursor = res_data.next_cursor
        res_data.alerts.to_ary
      end

      sig do
        override.params(
          alerts: T::Array[TurboscanInsightsAlert],
          args: T.untyped,
          repository_id: Integer,
          offset_item_id: T.any(Integer, T.nilable(String), [Integer, T.nilable(String)]),
          kwargs: T.untyped,
        ).void
      end
      def process_batch(alerts, *args, repository_id:, offset_item_id:, **kwargs)
        # Find and remove any revisions for alerts that are no longer returned by Turboscan
        process_orphaned_alerts(alerts, offset_item_id)

        # Because the batch may include "fake" initial revisions, we sort alerts by updated_at in decending order.
        # This way, we can evaluate the "real" revision before the "fake" initial revision.
        alerts_exceeding_retention_limit = Set.new
        alerts.sort_by { |a| (a.updated_at || a.created_at)&.to_time&.utc }.reverse_each do |alert|
          event_time = alert.updated_at&.to_time
          date_id = Date.id_from_time(event_time)
          is_initial_revision = alert.created_at&.to_time == alert.updated_at&.to_time

          if is_initial_revision && alerts_exceeding_retention_limit.include?(alert.id)
            report_reconciliation_skipped("exceeds_retention_limit", alert:)
            next
          end
          alerts_exceeding_retention_limit << alert.id if date_id < Date.min_next_date_id

          purge_redundant_revisions(alert)

          revision =
            T.let(CodeScanningAlertRevision
              .find_by(
                repository_id:,
                alert_id: alert.id, # TODO - update to read from alert_number once https://github.com/github/security-center/issues/6296 is complete.
                date_id:
              ), T.nilable(CodeScanningAlertRevision))

          # If we don't have a revision on this date, we need to create one.
          if revision.nil?
            GitHub.dogstats.increment(
              "security_overview_analytics.reconciliation.deviation",
              tags: all_stats_tags + ["deviation:missing_revision"]
            )
            CodeScanningAlertRevisionIngestionJob.perform_later(
              alert:,
              event_time:,
              deleted: false,
              source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT,
            )
            next
          end

          # In the rare occasion where an alert is updated _during_ reconciliation, it may be that our revision
          # is newer than that of the response payload. In that case, skip reconciling this alert.
          source_alert_updated_at = alert.updated_at&.to_time&.iso8601(3)&.to_time&.utc
          target_alert_updated_at = revision.alert_updated_at.iso8601(3)&.to_time&.utc
          if target_alert_updated_at > source_alert_updated_at
            report_reconciliation_skipped("old_source_alert_timestamp", alert:)
            next
          end

          # Check for deviations between the alert's current state and our latest revision
          alert_severity = \
            if alert.severity.is_a?(Symbol) && alert.severity != :NO_SECURITY_SEVERITY
              alert.severity.to_s
            end
          alert_resolution = \
            if alert.resolution.is_a?(Symbol) && alert.resolution != :NO_RESOLUTION
              ::Turboscan::Proto::ResultResolution.resolve(T.cast(alert.resolution, Symbol))&.to_i
            end

          deviations = T.let([], T::Array[Symbol])
          deviations << :severity if alert_severity != revision.alert_severity
          deviations << :tool if alert.tool_name != revision.tool
          deviations << :rule if alert.rule_sarif_identifier != revision.rule_sarif_identifier
          deviations << :resolved if alert.closed != revision.alert_resolved
          deviations << :resolved_at if alert.closed_at != revision.alert_resolved_at
          deviations << :resolution if alert_resolution != revision.alert_resolution
          deviations << :alert_id if alert.id != revision.alert_id

          # If the alert has any notable deviations, we need to correct them.
          if deviations.present?
            GitHub.dogstats.increment(
              "security_overview_analytics.reconciliation.deviation",
              tags: all_stats_tags + [*deviations.map { |d| "deviation:#{d}" }]
            )
            CodeScanningAlertRevisionIngestionJob.perform_later(
              alert:,
              event_time:,
              deleted: false,
              force_rewrite: true,
              source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT,
            )
            next
          end
        end
      end

      sig do
        override.params(
          alerts: T::Array[TurboscanInsightsAlert],
          kwargs: T.untyped
        ).returns(T::Boolean)
      end
      def has_next_batch?(alerts, **kwargs)
        next_cursor.present?
      end

      sig do
        override.params(
          alerts: T::Array[TurboscanInsightsAlert],
          args: T.untyped,
          kwargs: T.untyped
        ).returns([Integer, T.nilable(String)])
      end
      def next_batch_offset_item_id(alerts, *args, **kwargs)
        # Returns a tuple that represents the end of the current batch, both locally (by id) and remotely (by cursor).
        # item_id has to be alert id since the turboscan API always sorts with alert id.
        item_id = alerts.map(&:id).max
        [
          item_id || 0,
          next_cursor
        ]
      end

      sig { params(args: T::Array[T.untyped], options: T.untyped).void }
      def finalize_batch(*args, **options)
        # Because the hash lock is only on the `repository_id` parameter, enqueues for subsequent batches would fail.
        # Release here before the next batch is enqueued.
        clear_lock
      end

      sig { override.params(finished_successfully: T::Boolean, options: T.untyped).returns(T.untyped) }
      def ensure_perform(finished_successfully:, **options)
        if finished_successfully && !GitHub.enterprise?
          PostReconciliationRepoDeviationCountsJob.perform_with_delay(repository_id:, owner_id:, feature: "code-scanning")
        end
      end

      sig { returns(Reconciliation::Session) }
      memoize def session
        Reconciliation::Session.new(owner_id:, type: Initialization::Type::CodeScanningAlert.serialize)
      end

      sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
      def fanout_jobs
        [CodeScanningAlertRevisionIngestionJob]
      end

      protected

      sig { override.returns(T::Array[String]) }
      def stats_tags
        [
          "metric_type:code_scanning_alerts",
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

      sig { returns(Integer) }
      memoize def repository_id
        arguments.dig(0, :repository_id)
      end

      sig { returns(::Repository) }
      memoize def repository
        ::Repositories::Public.get_active_or_deleted!(repository_id)
      end

      sig { returns(Integer) }
      memoize def owner_id
        T.must(repository.owner&.id)
      end

      sig { returns(::Organization) }
      memoize def organization
        T.must(Organization.find_by(id: owner_id))
      end

      sig { returns(T.nilable(Time)) }
      memoize def session_started_at
        session.session_started_at
      end

      sig { returns(String) }
      memoize def session_id
        session.id
      end

      sig { returns(T.nilable(Time)) }
      memoize def last_session_started_at
        arguments.dig(0, :last_session_started_at)
      end

      private

      sig { returns(T::Boolean) }
      memoize def dry_run?
        FeatureFlagHelper.code_scanning_reconciliation_dry_run_mode?(organization)
      end

      sig { params(reason: String, reset: T::Boolean, alert: T.nilable(TurboscanInsightsAlert)).void }
      def report_reconciliation_skipped(reason, reset: false, alert: nil)
        # If required, reset session lock to the previous session run
        session.reset!(last_session_started_at:) if reset

        GitHub.logger.info(
          "Reconciliation skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": reason,
          "gh.security_overview_analytics.alert.number": alert&.id,
          "gh.security_overview_analytics.alert.updated_at": alert&.updated_at,
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
          alerts: T::Array[TurboscanInsightsAlert],
          offset_item_id: T.any(Integer, T.nilable(String), [Integer, T.nilable(String)]),
        ).void
      end
      def process_orphaned_alerts(alerts, offset_item_id)
        # Only process orphaned alerts on a "full" reconciliation - i.e. when the lockout expires.
        return false unless last_session_started_at.nil?

        # Find the last alert id from the previous batch.
        # We cannot replace this with alert number since API always sort with ids.
        last_alert_id = offset_item_id.is_a?(Array) ? offset_item_id.first : 0

        is_last_batch = !has_next_batch?(alerts)
        GitHub.dogstats.distribution_time("security_overview_analytics.reconciliation.process_orphaned_alerts.dist", tags: all_stats_tags) do
          rel =
            CodeScanningAlertRevision
              .where(repository_id:)
              .where("alert_id > ?", last_alert_id) # TODO - update to read from alert_number once https://github.com/github/security-center/issues/6296 is complete.

          if alerts.any?
            alert_ids = alerts.map(&:id).uniq
            rel = rel.where.not(alert_id: alert_ids) # TODO - update to read from alert_number once https://github.com/github/security-center/issues/6296 is complete.
            rel = rel.where("alert_id <= ?", T.must(alert_ids.max)) unless is_last_batch
          end

          orphaned_revisions_count = rel.count
          orphaned_alert_numbers_and_ids = T.let(rel.pluck(:alert_number, :alert_id), T::Array[Integer]).uniq
          unless dry_run?
            orphaned_alert_numbers_and_ids.each do |(alert_number, alert_id)|
              GitHub.dogstats.increment(
                "security_overview_analytics.reconciliation.deviation",
                tags: all_stats_tags + ["deviation:orphaned_alert"]
              )
              # Queue the ingestion job to handle deleting all revisions for this alert.
              # Note that we're faking the job params here, since this doesn't represent a change on the source.
              alert = TurboscanInsightsAlert.new(number: alert_number, id: alert_id, repository_id: repository_id)

              event_time = Time.now.utc
              CodeScanningAlertRevisionIngestionJob.perform_later(
                alert:,
                event_time:,
                deleted: true,
                source_event: OrganizationReconciliationJob::RECONCILIATION_EVENT,
              )
            end
          end

          # If number of alerts is large, send telemetry in batches to make it readable and so we don't break the entire log
          orphaned_alert_numbers_and_ids.each_slice(TELEMETRY_BATCH_SIZE) do |batch|
            GitHub.logger.info(
              dry_run? ? "Orphaned alerts would be processed" : "Orphaned alerts processed.",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.security_overview_analytics.job.orphaned_revisions_count": orphaned_revisions_count.size,
              "gh.security_overview_analytics.job.orphaned_alerts_count": orphaned_alert_numbers_and_ids.size,
              "gh.security_overview_analytics.job.orphaned_alerts_number_and_id": batch,
              "gh.security_overview_analytics.job.is_last_batch": is_last_batch,
              "gh.security_overview_analytics.job.is_empty_batch": alerts.empty?
            )
          end
        end
      end

      sig { params(alert: TurboscanInsightsAlert).void }
      def purge_redundant_revisions(alert)
        # Purges redundant revisions with date_id that is later than current alert's timestamp
        purge_revisions_later_than_current_alert(alert)

        # Purges duplicated revisions with date_id that is later than the latest revision
        purge_revisions_dup_after_latest(alert)
      end

      sig { params(alert: TurboscanInsightsAlert).void }
      def purge_revisions_later_than_current_alert(alert)
        # Everything is newer than the initial revision, so we can't purge it.
        is_initial_revision = alert.created_at&.to_time == alert.updated_at&.to_time
        return false if is_initial_revision

        rows_affected = T.let(0, Integer)
        alert_date_id = Date.id_from_time(alert.updated_at&.to_time)

        # TODO - update to read from alert_number once https://github.com/github/security-center/issues/6296 is complete.
        base_rel = CodeScanningAlertRevision.where(repository_id:, alert_id: alert.id)

        # Purge any revisions that are newer than the alert's updated_at timestamp.
        revisions_to_purge = base_rel
          .where("date_id > ?", alert_date_id)
          # Keep/skip any revisions that have been written since this reconciliation session started.
          .where("created_at < ?", session_started_at)
        return if revisions_to_purge.blank?

        rows_affected = revisions_to_purge.count if dry_run?

        unless dry_run?
          GitHub.dogstats.distribution_time("security_overview_analytics.reconciliation.purge_revisions_later_than_current_alert.dist", tags: all_stats_tags) do
            CodeScanningAlertRevision.throttle_writes do
              CodeScanningAlertRevision.transaction do
                rows_affected = revisions_to_purge.delete_all

                if rows_affected > 0
                  # Now that we've purged any newer revisions, we need to mark the new latest revision
                  new_latest_revision = base_rel
                    .where("date_id <= ?", alert_date_id)
                    .order(date_id: :desc)
                    .first&.lock!
                  new_latest_revision&.update(next_revision_date_id: Date::FUTURE_DATE_ID)
                end
              end
            end
          end

          GitHub.dogstats.count("security_overview_analytics.reconciliation.revisions_purged", rows_affected, tags: all_stats_tags)
        end

        GitHub.logger.info(
          dry_run? ? "Alert revisions would be purged" : "Alert revisions purged",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.alert.id": alert.id,
          "gh.security_overview_analytics.alert.number": alert.number,
          "gh.security_overview_analytics.alert.created_at": alert.created_at,
          "gh.security_overview_analytics.alert.updated_at": alert.updated_at,
          "gh.security_overview_analytics.revisions_purged": rows_affected,
        )
      end

      sig { params(alert: TurboscanInsightsAlert).void }
      def purge_revisions_dup_after_latest(alert)
        # Everything is newer than the initial revision, so we can't purge it.
        is_initial_revision = alert.created_at&.to_time == alert.updated_at&.to_time
        return false if is_initial_revision

        rows_affected = T.let(0, Integer)
        alert_date_id = Date.id_from_time(alert.updated_at&.to_time)

        # TODO - update to read from alert_number once https://github.com/github/security-center/issues/6296 is complete.
        base_rel = CodeScanningAlertRevision.where(repository_id:, alert_id: alert.id)

        latest_revision = base_rel.where(next_revision_date_id: Date::FUTURE_DATE_ID).to_a.first
        return if latest_revision.nil?

        revisions_existed_after_latest = base_rel
          .where("date_id > ?", latest_revision.date_id)
          # Keep/skip any revisions that have been written since this reconciliation session started.
          .where("created_at < ?", session_started_at)
          .to_a
        return if revisions_existed_after_latest.empty?

        revisions_to_purge = T.let([], T::Array[CodeScanningAlertRevision])
        revisions_existed_after_latest.each do |revision|
          # Fixing know broken revision pattern: revisions with the same data existed after the latest revision.
          # Solution: just delete them.
          next revisions_to_purge << revision if revision == latest_revision

          # As we try to fix revisions based on known pattern, log telemetry for those that we do not expect to fix here.
          GitHub.logger.info(
            "Unexpected alert revision found.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.alert.id": alert.id,
            "gh.security_overview_analytics.alert.number": alert.number,
            "gh.security_overview_analytics.alert.revision": revision.attributes.inspect,
          )
          GitHub.dogstats.increment("security_overview_analytics.reconciliation.unexpected_revision", tags: all_stats_tags)
        end
        return if revisions_to_purge.empty?

        rows_affected = revisions_to_purge.size if dry_run?

        unless dry_run?
          GitHub.dogstats.distribution_time("security_overview_analytics.reconciliation.purge_revisions_dup_after_latest.dist", tags: all_stats_tags) do
            CodeScanningAlertRevision.throttle_writes_with_retry do
              rows_affected = CodeScanningAlertRevision.where(id: revisions_to_purge.map(&:id)).delete_all
            end
          end

          GitHub.dogstats.count("security_overview_analytics.reconciliation.redundant_revisions_purged", rows_affected, tags: all_stats_tags)
        end

        revisions_to_purge.each do |revision|
          GitHub.logger.info(
            dry_run? ? "Alert revision would be purged" : "Alert revision purged",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.alert.id": alert.id,
            "gh.security_overview_analytics.alert.number": alert.number,
            "gh.security_overview_analytics.alert.revision": revision.attributes.inspect,
          )
        end
      end
    end
  end
end
