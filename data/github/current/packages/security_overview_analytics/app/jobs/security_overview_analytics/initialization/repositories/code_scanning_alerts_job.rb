# typed: strict
# frozen_string_literal: true

require "turboscan"

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class CodeScanningAlertsJob < BaseBatchedJob
        include GitHub::Memoizer
        include FanoutThrottler
        include BatchedJobThrottler

        TurboscanInsightsAlert = ::Turboscan::Proto::InsightsAlert

        queue_as :security_overview_analytics_repository_code_scanning_alerts_initialization

        class TurboscanError < StandardError; end

        retry_on \
          TurboscanError,
          wait: :polynomially_longer,
          attempts: 6

        # The base BatchedJob adds several parameters that effectively make every enqueue unique.
        # Limit this to only the input parameters. Requires manually clearing the lock in finalize_batch.
        locked_by timeout: 15.minutes, key: ->(job) do
          repository_id = job.arguments.dig(0, :repository_id)
          DEFAULT_LOCK_STRINGIFY_PROC.call([repository_id])
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
            offset_item_id: T.any(Integer, T.nilable(String)),
            kwargs: T.untyped,
          )
          .returns(T::Array[TurboscanInsightsAlert])
        end
        def next_batch(*args, repository_id:, offset_item_id:, **kwargs)
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
              "security_overview_analytics.initialization.code_scanning_alerts.error",
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
            kwargs: T.untyped,
          ).void
        end
        def process_batch(alerts, *args, repository_id:, **kwargs)
          # Because the batch may include "fake" initial revisions, we sort alerts by updated_at in decending order.
          # This way, we can evaluate the "real" revision before the "fake" initial revision.
          alerts_exceeding_retention_limit = Set.new
          alerts.sort_by { |a| (a.updated_at || a.created_at)&.to_time&.utc }.reverse_each do |alert|
            event_time = alert.updated_at&.to_time
            date_id = Date.id_from_time(event_time)

            # If we already have revisions for this alert+date, it indicates a collision with event ingestion.
            # We should skip this alert and continue processing.
            is_initial_revision = alert.created_at&.to_time == alert.updated_at&.to_time
            # TODO - update to read from alert_number once https://github.com/github/security-center/issues/6296 is complete.
            existing_revision = CodeScanningAlertRevision.find_by(repository_id:, alert_id: alert.id, date_id:)

            if existing_revision.present? && (
              is_initial_revision || # Skips initial revision if a revision already exists
              existing_revision.alert_updated_at > existing_revision.alert_created_at # Skips revision if a non-initial revision already exists
            )
              GitHub.logger.info("CodeScanningAlertRevision already exists.", {
                "gh.alert.id": alert.id,
              })
              GitHub.dogstats.increment(
                "security_overview_analytics.initialization.code_scanning_alerts.skipped",
                tags: all_stats_tags + ["cause:revisions_already_exist"]
              )
              next
            elsif is_initial_revision && alerts_exceeding_retention_limit.include?(alert.id)
              GitHub.logger.info("Initial revision exceeds retention limit.", {
                "gh.alert.id": alert.id,
              })
              GitHub.dogstats.increment(
                "security_overview_analytics.initialization.code_scanning_alerts.skipped",
                tags: all_stats_tags + ["cause:exceeds_retention_limit"]
              )
              next
            end

            alerts_exceeding_retention_limit << alert.id if date_id < Date.min_next_date_id

            CodeScanningAlertRevisionIngestionJob.perform_later(
              alert:,
              event_time:,
              deleted: false,
              source_event: TenantBaseJob::INITIALIZATION_EVENT,
            )
          end
        end

        sig do
          override.params(
            alerts: T::Array[T::Hash[Symbol, T.untyped]],
            kwargs: T.untyped
          ).returns(T::Boolean)
        end
        def has_next_batch?(alerts, **kwargs)
          next_cursor.present?
        end

        sig do
          override.params(
            alerts: T::Array[T::Hash[Symbol, T.untyped]],
            args: T.untyped,
            kwargs: T.untyped
          ).returns(T.nilable(T.any(Integer, String)))
        end
        def next_batch_offset_item_id(alerts, *args, **kwargs)
          next_cursor
        end

        sig { params(args: T::Array[T.untyped], options: T.untyped).void }
        def finalize_batch(*args, **options)
          # Because the hash lock is only on the `repository_id` parameter, enqueues for subsequent batches would fail.
          # Release here before the next batch is enqueued.
          clear_lock
        end

        sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
        def fanout_jobs
          # If any of the below job queue is being throttled, delay the entire batch.
          [CodeScanningAlertRevisionIngestionJob]
        end

        protected

        sig { override.returns(T::Boolean) }
        def should_initialize?
          unless SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
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

        private

        sig { returns(::Organization) }
        memoize def organization
          T.must(Organization.find_by(id: repository.owner_id))
        end

        sig { params(reason: Symbol).void }
        def instrument_repository_skipped(reason)
          GitHub.logger.info(
            "Initialization skipped.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.job.reason": reason,
          )
          GitHub.dogstats.increment(
            "security_overview_analytics.initialization.code_scanning_alerts.skipped",
            tags: all_stats_tags + ["reason:#{reason}"]
          )
        end
      end
    end
  end
end
