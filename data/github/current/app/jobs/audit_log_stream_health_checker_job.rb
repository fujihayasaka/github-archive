# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# This job checks the health of all audit log streams and disables the streams that are consistently failing.
# The job runs every 24 hours and checks the health of all audit log streams.
# If a stream fails the health check, the job will retry the stream check in the next job run.
# If the stream fails MAX_JOB_RUNS consecutive times, the stream will be disabled and an email will be sent to the business owner.
class AuditLogStreamHealthCheckerJob < ApplicationJob

  schedule interval: 24.hours
  queue_as :audit_log_stream_health_checker
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  BATCH_SIZE = 250
  # The max number of retries within a single job run for each failed stream
  MAX_RETRIES = 5
  # The max number of job runs before the failing streams are disabled
  MAX_JOB_RUNS = 16
  # How long each 1 to MAX_JOB_RUNS job runs should be delayed
  RETRY_JOB_DELAY = 30.minutes


  # @param [Array<Integer>] business_ids if present, only check streams for these businesses
  # @param [Integer]        job_runs the number of times this job has run, used to determine
  #                         that a stream should be disabled for those streams that have failed MAX_JOB_RUNS times
  sig { params(business_ids: T::Array[Integer], job_runs: Integer).void }
  def perform(business_ids = [], job_runs = 0)
    # bussiness ids that should be retryed in a subequent job run
    retry_ids = Set.new

    ActiveRecord::Base.connected_to(role: :reading) do
      query = AuditLogStreamConfiguration.includes(:business)
      query = query.where(business_id: business_ids) if business_ids.present?
      query = query.where(enabled: true)

      query.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        batch.each do |stream|
          business = stream.business
          next unless business.present?

          if business.feature_flag_enabled_or_raise?(:audit_log_health_checker_skip) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            GitHub.logger.info("skip streaming health check", "gh.business.id" => business.id)
            next
          end

          next if check_successful?(stream)

          # we'll retry the stream check in the next job run
          if job_runs < MAX_JOB_RUNS
            retry_ids << business.id
            next
          end

          if !business.feature_flag_enabled?(:audit_log_health_checker_send_email, default: false)
            GitHub.logger.info("skip streaming health check email", "gh.business.id" => business.id)
            GitHub.dogstats.increment("audit_log.disabled_stream", tags: ["business_id:#{business.id}", "noop:true"])
            next
          end

          # Disable the stream as it has failed MAX_JOB_RUNS times
          ActiveRecord::Base.connected_to(role: :writing) do
            stream.update(enabled: false, gh_staff_disabled: true, paused_at: DateTime.now.utc) unless GitHub.enterprise?
            BusinessMailer.audit_log_stream_disabled_warning(business, stream.sink.sink_type).deliver_later
          end
          GitHub.dogstats.increment("audit_log.disabled_stream", tags: ["business_id:#{business.id}", "noop:false"])
        end
      end
    end

    return unless retry_ids.to_a.present?

    GitHub.logger.info("Retry Audit Log stream health check", "gh.business.ids": retry_ids.to_a, "gh.job.runs": job_runs)
    AuditLogStreamHealthCheckerJob.set(wait: RETRY_JOB_DELAY).perform_later(retry_ids.to_a, job_runs + 1)
  end

  private

  # Check if the stream check is successful
  # @param [AuditLogStreamConfiguration] stream
  def check_successful?(stream)
    retries = 0
    begin
      result = stream.check_sink(stream.business, stream.sink)
    rescue Faraday::Error, Faraday::TimeoutError => e
      retries += 1

      if retries <= MAX_RETRIES
        sleep 0.5
        retry
      end

      GitHub.logger.error("Error checking Audit Log stream",
        exception: e,
        "gh.business.id": stream.business_id,
      )
    end

    result == "ok"
  end
end
