# typed: true
# frozen_string_literal: true

# The VulnerableVersionRangeAlertingProcess model belongs to a
# VulnerabilityAlertingEvent and may have siblings. Only a
# VulnerabilityAlertingEvent with a reason of "on_process_alerts" will have
# associated VulnerableVersionRangeAlertingProcess records.
#
# Tracking the alerting process across an entire VulnerableVersionRange is
# something we only do when we're processing alerts via Staff Tools.
class VulnerableVersionRangeAlertingProcess < ApplicationRecord::Notify
  include GitHub::Memoizer

  PROCESSING_EXPIRES_DURATION = T.let(1.month, ActiveSupport::Duration)
  PROCESSING_STALLED_DURATION = T.let(8.hours, ActiveSupport::Duration)

  belongs_to :vulnerability_alerting_event
  belongs_to :vulnerable_version_range

  scope :not_processed, -> { where(processed_at: nil) }

  # Determines which Dependency Graph service should provide the detection query for this process, default: DG_API
  enum :detection_provider, { DG_API: 0, DGP: 1 }

  # Public: Marks the alerting process as processing in Redis. Be warned that
  # these values expire! The processing-active key is intended to expire soon
  # so that we can detect when processing has stalled by checking for the
  # continued presence of this key.
  sig { returns(T::Boolean) }
  def processing!
    redis.pipelined do |pipeline|
      pipeline.set(processing_key, Time.now.to_i.to_s, nx: true, ex: PROCESSING_EXPIRES_DURATION.in_seconds)
      pipeline.set(processing_active_key, "1", ex: PROCESSING_STALLED_DURATION.in_seconds)
      pipeline.set(alert_count_key, "0", nx: true, ex: PROCESSING_EXPIRES_DURATION.in_seconds)
    end

    true
  end

  # Public: Returns whether the alerting process is still processing alerts.
  # Specifically, this method checks whether processing has begun but has not
  # yet finished. This method will return true even if processing has stalled.
  # See: #processing_stalled?
  sig { returns(T::Boolean) }
  def processing?
    !processed? && redis.exists?(processing_key)
  end

  # Public: Immediately mark the alerting process as stalled. This can be used
  # when the precise moment of processing failure is known.
  sig { returns(T::Boolean) }
  def processing_stalled!
    return false unless processing?

    redis.del(processing_active_key)

    true
  end

  # Public: Returns whether the alert processing has stalled, defined by no
  # activity in the past PROCESSING_STALLED_DURATION.
  sig { returns(T::Boolean) }
  def processing_stalled?
    processing? && !redis.exists?(processing_active_key)
  end

  # Public: Marks the alerting process as processed. This sets the processed_at
  # timestamps and performs Redis cleanup. The alert-count key is preserved
  # until it expires because the information may be useful after processing and
  # we have no logic conditional upon its presence.
  #
  # If this alerting process is the last of its siblings to be finish
  # processing, we also mark the parent alerting event as processed.
  sig { returns(T::Boolean) }
  def processed!
    return false if processed?

    ActiveRecord::Base.connected_to(role: :writing) do
      touch(:processed_at)

      # Check to see if any of the alerting event's alerting processes are still
      # in flight. If not, mark the alerting event as processed too. This will
      # kick off a TriggerCombinedVulnerabilityAlertEmailsJob.
      #
      # See: VulnerabilityAlertingEvent#processed!
      if vulnerability_alerting_event&.
          vulnerable_version_range_alerting_processes&.
          not_processed&.
          none?
        vulnerability_alerting_event&.processed!
      end
    end

    redis.del(processing_key, processing_active_key)

    dg_process_manager = DependencyGraph::VulnerabilityScanning::AdvisoryBroadcastProcessManager.from_slug(detection_provider)

    # Check if this process is using the lead detection provider and perform any follow-up work.
    #
    # Under most circumstances, there will only be one process queued per vulnerable_version_range,
    # but if Dependency Graph is actively migrating an ecosystem, there will be one process for
    # DG-API and one for DGP - but only one should enqueue this follow-up work.
    if vulnerable_version_range && dg_process_manager.lead_processor_for?(T.must(vulnerable_version_range))
      ReprocessRepositoryAlertsWithSnapshotDependencyJob.perform_later(vulnerable_version_range)
    end

    true
  end

  # Public: Returns whether the alerting process has finished processing.
  sig { returns(T::Boolean) }
  def processed?
    !!processed_at
  end

  # Public: Get the current number of alerts created by this alerting process.
  # Be warned that this value is stored in Redis and will expire! If the value
  # isn't set yet or already expired, this method will return nil.
  sig { returns(T.nilable(Integer)) }
  def alert_count
    redis.get(alert_count_key)&.to_i
  end

  # Public: Increment the number of alerts created by this alerting process.
  # This method also refreshes the processing-active key's expiration to
  # prevent this alerting process from being marked as stalled.
  sig { params(amount: Integer).void }
  def increment_alert_count(amount)
    redis.pipelined do |pipeline|
      pipeline.incrby(alert_count_key, amount) if amount > 0
      pipeline.set(processing_active_key, "1", ex: PROCESSING_STALLED_DURATION.in_seconds)
    end
  end

  sig { returns(T::Array[String]) }
  memoize def datadog_tags
    datadog_tags = vulnerability_alerting_event&.datadog_tags.dup

    datadog_tags.concat([
      "process_id:#{id}",
      "detection_provider:#{detection_provider}",
    ]) unless datadog_tags.nil?

    if vulnerable_version_range
      datadog_tags.concat([
        "range_id:#{vulnerable_version_range&.id}",
        "ecosystem:#{vulnerable_version_range&.ecosystem}",
      ]) unless datadog_tags.nil?
    end

    datadog_tags || []
  end

  sig { returns(GitHub::Progress::Client) }
  memoize def progress
    GitHub::Progress::Client.new("vulnerable-version-range-alerting-process.#{id}")
  end

  private

  sig { returns(Redis) }
  def redis
    GitHub.legacy_redis
  end

  sig { returns(String) }
  def key_prefix
    "vulnerable-version-range-alerting-process.#{id}."
  end

  sig { returns(String) }
  def processing_key
    key_prefix + "processing"
  end

  sig { returns(String) }
  def processing_active_key
    key_prefix + "processing-active"
  end

  sig { returns(String) }
  def alert_count_key
    key_prefix + "alert-count"
  end
end
