# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"
require "turboscan"

module SecurityOverviewAnalytics
  class Backfill::CodeScanningAlertNumberJob < BatchedJob
    extend T::Sig
    include GitHub::Memoizer
    include GitHub::SecurityCenter::LoggingHelper

    class TurboscanError < StandardError; end

    queue_as :security_overview_analytics_repository_data_cleanup

    retry_on_dirty_exit
    retry_on_recoverable_exceptions
    retry_on(TurboscanError, wait: :polynomially_longer)
    retry_on(GitHub::Restraint::UnableToLock, wait: 10.seconds, attempts: 100)

    locked_by timeout: 15.minutes, key: ->(job) do
      repository_id = job.arguments.dig(0, :repository_id)
      DEFAULT_LOCK_STRINGIFY_PROC.call([repository_id])
    end

    resolve_tenant_context do |job_args|
      Repositories::Public.resolve_tenant(id: job_args[:repository_id])
    end

    around_perform do |_job, block|
      if GitHub.flipper[:security_center_backfill_code_scanning_alert_number].enabled?
        block.call
      else
        clear_lock
      end
    end

    sig { returns(T.nilable(String)) }
    attr_reader :next_cursor

    sig { override.params(args: T.untyped, kwargs: T.untyped).void }
    def initialize(*args, **kwargs)
      @next_cursor = T.let(nil, T.nilable(String))
      super(*T.unsafe(args), **kwargs)
    end

    sig { override.params(args: T.untyped, kwargs: T.untyped).void }
    def perform(*args, **kwargs)
      log_timing(step: "perform") do
        GitHub::Restraint.new.lock!(T.must(self.class.name), restraint_lock_num_concurrent_jobs, restraint_lock_ttl_sec) do
          super(*T.unsafe(args), **kwargs)
        end
      end
    end

    sig do
      override
        .params(
          args: T.untyped,
          offset_item_id: T.any(Integer, T.nilable(String)),
          repository_id: Integer,
          kwargs: T.untyped
        )
        .returns(T::Array[Turboscan::Proto::InsightsAlert])
    end
    def next_batch(*args, offset_item_id:, repository_id:, **kwargs)
      log_timing(step: "next_batch") do
        next_cursor = offset_item_id.nil? || offset_item_id.is_a?(Integer) ? nil : offset_item_id
        req = ::Turboscan::Proto::GetAlertsForInsightsBackfillRequest.new(
          repository_id:,
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
            "security_overview_analytics.backfill.code_scanning_alert_number_job.code_scanning_alerts.error",
            tags: all_stats_tags + ["cause:turboscan_error"]
          )
          raise TurboscanError
        end

        @next_cursor = res_data.next_cursor
        res_data.alerts.to_a
      end
    end

    sig do
      override.params(
        ts_alerts: T::Array[Turboscan::Proto::InsightsAlert],
        args: T.untyped,
        repository_id: Integer,
        kwargs: T.untyped
      ).void
    end
    def process_batch(ts_alerts, *args, repository_id:, **kwargs)
      log_timing(step: "process_batch") do
        if ts_alerts.blank?
          log_info("No alerts to process")
          return
        end

        existing_backfilled_revisions = CodeScanningAlertRevision
          .where(alert_id: ts_alerts.map(&:id), repository_id: repository_id)
          .where("alert_id <> alert_number")
          .group_by(&:alert_id)

        existing_pending_revisions = CodeScanningAlertRevision
          .where(alert_id: ts_alerts.map(&:id), repository_id: repository_id)
          .where("alert_id = alert_number")
          .group_by(&:alert_id)

        num_revs_to_bulk_update = 0
        num_bulk_updated_rows = 0
        num_revs_to_replay = 0
        alerts_without_number = T.let([], T::Array[Integer])

        # Ensure we're only processing unique id and numbers because turboscan will return "fake" initial revisions
        ts_alerts.map { |alert| [alert.id, alert.number] }.uniq.each do |ts_id, ts_number|
          existing_pending_revisions_for_alert = existing_pending_revisions[ts_id]
          next if existing_pending_revisions_for_alert.blank?

          existing_backfilled_revisions_for_alert = existing_backfilled_revisions[ts_id]
          existing_alert_number = existing_backfilled_revisions_for_alert&.first&.alert_number
          if ts_number > 0 && existing_alert_number.present? && existing_alert_number != ts_number
            log_info(
              "Unexpected alert number",
              "gh.security_overview_analytics.existing_alert_number": existing_alert_number,
              "gh.security_overview_analytics.ts_number": ts_number
            )
          end

          # 1. Workaround 0 numbers from turboscan.
          # 2. Use existing alert_number instead of the one from turboscan to priorize complete revision chain. (easier to remediate)
          if ts_number == 0
            alert_number = existing_alert_number || ts_id
            alerts_without_number << ts_id
          else
            alert_number = existing_alert_number || ts_number
          end

          if existing_backfilled_revisions_for_alert.present? && replay_mode?
            revisions_sort_by_date_id = existing_pending_revisions_for_alert.sort_by(&:date_id)
            replay_revisions(revisions_sort_by_date_id, alert_number:)
            num_revs_to_replay += revisions_sort_by_date_id.size
          else
            duplicated_revisions = T.let([], T::Array[CodeScanningAlertRevision])
            if existing_backfilled_revisions_for_alert.present?
              backfilled_revisions_date_ids = Set.new(existing_backfilled_revisions_for_alert.map(&:date_id))
              existing_pending_revisions_for_alert.each do |rev|
                if backfilled_revisions_date_ids.include?(rev.date_id)
                  log_info(
                    "Duplicated revision found",
                    "gh.security_overview_analytics.id": rev.id,
                    "gh.security_overview_analytics.date_id": rev.date_id,
                    "gh.security_overview_analytics.alert_id": rev.alert_id,
                    "gh.security_overview_analytics.alert_number": rev.alert_number
                  )
                  duplicated_revisions << rev
                  num_revs_to_replay += 1
                  next
                end
              end
            end

            # Replay duplicated revisions with proper alert_number through upserter and remove the replayed revisions
            if GitHub.flipper[:security_center_backfill_code_scanning_alert_number_process_duplicated_revisions].enabled?
              replay_revisions(duplicated_revisions.sort_by(&:date_id), alert_number:)
            end

            # Bulk update ignores duplicated revisions to avoid db errors
            revisions_to_update = existing_pending_revisions_for_alert.map(&:id) - duplicated_revisions.map(&:id)
            num_revs_to_bulk_update += revisions_to_update.size
            next if revisions_to_update.empty?

            if is_dry_run?
              num_bulk_updated_rows += revisions_to_update.size
            else
              CodeScanningAlertRevision.throttle_writes_with_retry do
                num_bulk_updated_rows += CodeScanningAlertRevision
                  .where(id: revisions_to_update)
                  .update_all(alert_number: alert_number, updated_at: Time.current.utc)
              end
            end
          end
        end

        log_info(
          is_dry_run? ? "Would have updated alert numbers" : "Updated alert numbers",
          "gh.security_overview_analytics.num_revs_to_bulk_update": num_revs_to_bulk_update,
          "gh.security_overview_analytics.num_bulk_updated_rows": num_bulk_updated_rows,
          "gh.security_overview_analytics.num_revs_to_replay": num_revs_to_replay,
          "gh.security_overview_analytics.alerts_without_number": alerts_without_number
        )
      end
    end

    sig { params(revisions: T::Array[CodeScanningAlertRevision], alert_number: Integer).void }
    def replay_revisions(revisions, alert_number:)
      return if revisions.empty?

      upsert_inputs = revisions.sort_by(&:date_id).map do |rev|
        {
          payload: ::SecurityOverviewAnalytics::CodeScanningAlertRevision::UpdatePayload.new(
            alert_created_at: rev.alert_created_at,
            alert_id: rev.alert_id,
            alert_resolution: rev.alert_resolution,
            alert_resolved: rev.alert_resolved,
            alert_resolved_at: rev.alert_resolved_at,
            alert_severity: rev.alert_severity,
            alert_updated_at: rev.alert_updated_at,
            language: rev.language,
            ref: rev.ref,
            rule_sarif_identifier: rev.rule_sarif_identifier,
            tool: rev.tool
          ),
          alert_number:,
          date_id: rev.date_id,
          repository_id: rev.repository_id
        }
      end

      unless is_dry_run?
        CodeScanningAlertRevision.throttle_writes_with_retry do
          upsert_inputs.each do |input|
            ::SecurityOverviewAnalytics::CodeScanningAlertRevision.upsert_revision(
              input[:payload],
              alert_number: input[:alert_number],
              date_id: input[:date_id],
              repository_id: input[:repository_id]
            )
          end
        end

        CodeScanningAlertRevision.throttle_writes_with_retry do
          CodeScanningAlertRevision.where(id: revisions.map(&:id)).delete_all
        end
      end
    end

    sig { returns(T::Boolean) }
    memoize def is_dry_run?
      GitHub.flipper[:security_center_backfill_code_scanning_alert_number_dry_run].enabled?
    end

    sig { returns(T::Boolean) }
    memoize def replay_mode?
      backfill_mode = arguments.dig(0, :backfill_mode)
      return false if backfill_mode.nil?

      replay_mode_value = :replay
      if backfill_mode.is_a?(String)
        backfill_mode.downcase.to_sym == replay_mode_value
      else
        backfill_mode == replay_mode_value
      end
    end

    sig do
      override.params(args: T.untyped, kwargs: T.untyped).returns(T::Boolean)
    end
    def has_next_batch?(*args, **kwargs)
      next_cursor.present?
    end

    sig { override.params(args: T.untyped, kwargs: T.untyped).returns(T.nilable(T.any(Integer, String))) }
    def next_batch_offset_item_id(*args, **kwargs)
      next_cursor
    end

    sig { override.params(args: T.untyped, options: T.untyped).void }
    def finalize_batch(*args, **options)
      clear_lock
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({ app: "github-security-center" })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      kwargs = arguments[0] || {}
      organization_id = arguments.dig(0, :organization_id)
      repository_id = arguments.dig(0, :repository_id)
      initial_start = kwargs.fetch(:initial_start, Time.current.utc)

      super.merge({
        "gh.batched_job.initial_start" => initial_start,
        "gh.batched_job.offset_item_id" => kwargs[:offset_item_id],
        "gh.batched_job.restraint_lock_num_concurrent_jobs" => restraint_lock_num_concurrent_jobs,
        "gh.batched_job.restraint_lock_ttl_sec" => restraint_lock_ttl_sec,
        "gh.job.restraint_lock.retry.count" => exception_executions[[GitHub::Restraint::UnableToLock].to_s] || 0,
        "gh.org.id" => organization_id,
        "gh.repo.id" => repository_id,
        "gh.security_overview_analytics.replay_mode" => replay_mode?
      })
    end

    sig { returns(Integer) }
    def restraint_lock_num_concurrent_jobs
      # percentage_of_actors_value ranges from 0.01 to 100
      GitHub
        .flipper["soa_backfill_code_scanning_alert_number_job_restraint_lock_num_concurrent_jobs".to_sym]
        .percentage_of_actors_value
        .floor
    end

    sig { returns(Integer) }
    def restraint_lock_ttl_sec
      # percentage_of_actors_value ranges from 0.01 to 100
      GitHub
        .flipper["soa_backfill_code_scanning_alert_number_job_restraint_lock_ttl_minutes".to_sym]
        .percentage_of_actors_value
        .floor
        .minutes
        .to_i
    end
  end
end
