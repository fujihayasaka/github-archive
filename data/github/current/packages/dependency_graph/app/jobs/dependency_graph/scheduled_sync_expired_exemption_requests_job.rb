# typed: strict
# frozen_string_literal: true

require "oss_license_compliance/twirp/oss_license_compliance_client"

module DependencyGraph
  class ScheduledSyncExpiredExemptionRequestsJob < BatchedJob
    include DependencyGraph::RetryJob
    include GitHub::Memoizer

    retry_on_dirty_exit

    METRICS_PREFIX = "dependency_graph.jobs.scheduled_sync_expired_exemption_requests"

    # Queue name for processing job
    queue_as :license_compliance_sync_expired_exemption_requests

    # Runs daily (skipped on GitHub Enterprise Server)
    schedule interval: 1.day, condition: -> { !GitHub.enterprise? }

    # Processes a batch of expired exemption requests.
    # Inherited from BatchedJob, which sets BATCH_SIZE to 100.
    # For each batch:
    # - Calls OLC expire_alert_dismissal_by_batch
    # - Updates all successfully expired exemption requests to :cancelled status in a single db query
    #
    # After processing, BatchedJob automatically schedules another job if batch.size >= BATCH_SIZE,
    # using the highest ID from the current batch as offset_item_id. The batch returned by next_batch()
    # is what will be processed in the next job.
    sig { params(batch: T::Array[Exemptions::ExemptionRequest], args: T.untyped, options: T.untyped).void }
    def process_batch(batch, *args, **options)
      GitHub.logger.info("Starting batch processing",
        batch_size: batch.size,
        batch_first_id: batch.first&.id,
        batch_last_id: batch.last&.id,
      )

      dismissals = []
      exemption_lookup = {}

      batch.each do |exemption_request|
        alert_number = exemption_request.metadata["alert_number"]&.to_i
        next if alert_number.nil?

        dismissals << {
          repository_id: exemption_request.resource_owner_id,
          alert_number: alert_number,
          expiry_timestamp: Google::Protobuf::Timestamp.new(seconds: exemption_request.expires_at.to_i)
        }

        # Create lookup key (repository_id + alert number) for mapping response back to exemption request
        lookup_key = "#{exemption_request.resource_owner_id}_#{alert_number}"
        exemption_lookup[lookup_key] = exemption_request
      end

      if dismissals.empty?
        GitHub.logger.info("No valid expired exemption requests to process")
        return
      end

      response = expire_alert_dismissals_batch_with_logging(dismissals)
      return unless response

      exemption_request_ids = []

      response.expired_alerts.each do |expired_alert|
        lookup_key = "#{expired_alert.repository_id}_#{expired_alert.alert_number}"
        exemption_request = exemption_lookup[lookup_key]

        if exemption_request
          exemption_request_ids << exemption_request.id

          GitHub.logger.info("Successfully expired alert in olc",
            exemption_request_id: exemption_request.id,
            repository_id: expired_alert.repository_id,
            alert_number: expired_alert.alert_number
          )
        end
      end

      # Emit metrics for alerts expired and skipped in OLC
      expired_count = response.expired_alerts.size
      GitHub.dogstats.increment(
        "#{METRICS_PREFIX}.alerts_expired_total",
        by: expired_count,
        tags: all_stats_tags
      )

      skipped_count = dismissals.size - response.expired_alerts.size
      GitHub.dogstats.increment(
        "#{METRICS_PREFIX}.alerts_skipped_total",
        by: skipped_count,
        tags: all_stats_tags
      )

      # Batch update all successfully expired exemption requests
      if exemption_request_ids.any?
        Exemptions::ExemptionRequest.throttle do
          with_write do
            Exemptions::ExemptionRequest
              .where(id: exemption_request_ids)
              .update_all(status: :cancelled)
          end
        end
      end

      is_final_batch = batch.size < BATCH_SIZE

      GitHub.logger.info("Completed batch processing",
        batch_size: batch.size,
        is_final_batch: is_final_batch,
        alerts_expired_count: expired_count,
        alerts_skipped_count: skipped_count,
        exemption_requests_cancelled_count: exemption_request_ids.size,
      )
    end

    private

    sig do
      params(
        dismissals: T::Array[T::Hash[Symbol, T.untyped]]
      ).returns(T.nilable(OSSLicenseCompliance::V0::ExpireAlertDismissalByBatchResponse))
    end
    def expire_alert_dismissals_batch_with_logging(dismissals)
      response = license_compliance_client.expire_alert_dismissal_by_batch(dismissals: dismissals)

      if response.expired_alerts.size < dismissals.size
        GitHub.logger.info("Not all alerts were expired in olc",
          dismissals_sent: dismissals.size,
          alerts_expired: response.expired_alerts.size,
        )
      end
      response
    rescue StandardError => e
      Failbot.report(e,
        dismissals_count: dismissals.size
      )
      GitHub.logger.error("Failed to expire alerts in olc",
        dismissals_count: dismissals.size,
        error: e.message
      )
      # Return nil to skip processing
      nil
    end

    # Fetches the next batch of expired exemption requests to process.
    # Inherited from BatchedJob
    # Returns only:
    # - License compliance closure exemption requests (specific request_type)
    # - With Repository as resource_owner_type
    # - In "pending" status (not yet approved/rejected/cancelled)
    # - That have expired (expires_at < timestamp)
    # - With ID > offset_item_id (for pagination)
    # Ordered by ID and limited to BATCH_SIZE (100 records)
    sig { params(args: T.untyped, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(T::Array[Exemptions::ExemptionRequest]) }
    def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      Exemptions::ExemptionRequest
        .where(
          request_type: DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE,
          resource_owner_type: "Repository",
          status: "pending"
        )
        .where("expires_at < ?", timestamp)
        .where("id > ?", offset_item_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a
    end

    sig { returns(OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient) }
    memoize def license_compliance_client
      OSSLicenseCompliance::Twirp::OSSLicenseComplianceClient.new
    end
  end
end
