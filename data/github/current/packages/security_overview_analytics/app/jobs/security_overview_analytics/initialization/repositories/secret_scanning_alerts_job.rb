# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

module SecurityOverviewAnalytics
  class Initialization
    module Repositories
      class SecretScanningAlertsJob < BaseBatchedJob
        extend T::Sig
        include GitHub::Memoizer

        SecretScanningMetricsAPI = ::GitHub::Proto::SecretScanning::Metrics::V1

        class TokenScanningServiceMetricsApiError < StandardError; end

        queue_as :security_overview_analytics_repository_secret_scanning_alerts_initialization

        retry_on \
          TokenScanningServiceMetricsApiError,
          wait: :polynomially_longer,
          attempts: 6

        use_replicas ApplicationRecord::TokenScanningService,
          allow_replication_lag: [
            ApplicationRecord::Repositories,
            ApplicationRecord::Mysql1,
            ApplicationRecord::SecurityOverviewAnalytics
          ]

        locked_by timeout: 15.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

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
          .returns(T::Array[SecretScanningMetricsAPI::Alert])
        end
        def next_batch(*args, repository_id:, offset_item_id:, **kwargs)
          next_cursor = offset_item_id.is_a?(String) ? Base64.urlsafe_decode64(offset_item_id) : nil
          request = SecretScanningMetricsAPI::GetAlertsForInsightsBackfillRequest.new(
            repo_selector: SecretScanningMetricsAPI::RepoSelector.new(repository_id:),
            include_low_confidence: false, # Be explicit to exclude low confidence alerts
            updated_after: nil,
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
              "security_overview_analytics.initialization.repository_secret_scanning_alerts.error",
              tags: all_stats_tags + ["reason:#{TokenScanningServiceMetricsApiError.name&.underscore}}"]
            )
            raise TokenScanningServiceMetricsApiError
          end

          # Note:
          # By default next_cursor from API is in UTF-8 encoding where ruby will try to convert it to ASCII-8BIT
          # on the way out and fail. To workaround that, we force 64 encoding so we can decode it later into ASCII-8BIT
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
            kwargs: T.untyped,
          ).void
        end
        def process_batch(alerts, *args, repository_id:, **kwargs)
          alerts_ingested = T.let([], T::Array[Integer])
          # Because the batch may include "fake" initial revisions, we sort alerts by updated_at in decending order.
          # This way, we can evaluate the "real" revision before the "fake" initial revision.
          alerts_exceeding_retention_limit = Set.new
          alerts.sort_by { |a| (a.updated_at || a.created_at)&.to_time&.utc }.reverse_each do |alert|
            if alert.low_confidence
              instrument_alert_skipped(alert:, reason: :low_confidence_alert)
              next
            end

            event_time = alert.updated_at&.to_time
            date_id = Date.id_from_time(event_time)

            is_initial_revision = alert.created_at&.to_time == alert.updated_at&.to_time
            existing_revision = SecretScanningAlertRevision.find_by(repository_id: alert.repository_id, alert_number: alert.number, date_id:)
            if existing_revision.present? && (
              is_initial_revision || # Skips initial revision if a revision already exists
              existing_revision.alert_updated_at > existing_revision.alert_created_at # Skips revision if a non-initial revision already exists
            )
              instrument_alert_skipped(alert:, reason: :revision_already_exists)
              next
            elsif is_initial_revision && alerts_exceeding_retention_limit.include?(alert.number)
              instrument_alert_skipped(alert:, reason: :exceeds_retention_limit)
              next
            end

            alerts_exceeding_retention_limit << alert.number if date_id < Date.min_next_date_id

            SecretScanningAlertRevisionIngestionJob.perform_later(alert:, date_id:, event_time:,
              source_event: TenantBaseJob::INITIALIZATION_EVENT)
            alerts_ingested << alert.number
          end

          GitHub.logger.info(
            "Alerts processed.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.job.alerts_ingested": alerts_ingested,
          )
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
          ).returns(T.nilable(T.any(Integer, String)))
        end
        def next_batch_offset_item_id(alerts, *args, **kwargs)
          next_cursor
        end

        sig { override.returns(T::Boolean) }
        def should_initialize?
          unless SecurityCenter::SecurityFeatures.secret_scanning_enabled_for_instance?
            instrument_repository_skipped(:feature_unavailable)
            return false
          end

          if repository.deleted?
            instrument_repository_skipped(:repository_deleted)
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

        sig { params(reason: Symbol).void }
        def instrument_repository_skipped(reason)
          GitHub.logger.info(
            "Initialization skipped.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.reason": reason,
          )
          GitHub.dogstats.increment(
            "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped",
            tags: all_stats_tags + ["reason:#{reason}"]
          )
        end

        sig { params(alert: SecretScanningMetricsAPI::Alert, reason: Symbol).void }
        def instrument_alert_skipped(alert:, reason:)
          GitHub.logger.info(
            "Alert skipped.",
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.security_overview_analytics.alert": alert.to_h,
            "gh.security_overview_analytics.reason": reason,
          )
          GitHub.dogstats.increment(
            "security_overview_analytics.initialization.repository_secret_scanning_alerts.skipped",
            tags: all_stats_tags + ["reason:#{reason}"]
          )
        end
      end
    end
  end
end
