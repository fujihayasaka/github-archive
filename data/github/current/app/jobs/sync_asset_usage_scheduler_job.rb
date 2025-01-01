# typed: true
# frozen_string_literal: true

class SyncAssetUsageSchedulerJob < SyncAssetUsageJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on(*RETRYABLE_ERRORS)

  SYNC_INTERVAL = read_int_from_env("SYNC_INTERVAL", 60)
  MAX_KEYS = 1000  # maximum allowed per AWS S3 list_objects query
  KEYS_PER_SET = [read_int_from_env("KEYS_PER_SET", 100), MAX_KEYS].min
  SETS_PER_INTERVAL = read_int_from_env("SETS_PER_INTERVAL", 3)

  schedule interval: SYNC_INTERVAL.minutes, condition: -> { !GitHub.enterprise? }

  queue_as :sync_asset_usage

  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  def perform
    # Retrieve the timestamped key of the most recent log this job has
    # parsed
    return unless marker = Asset::SyncStatus.get(:all)

    scanner = log_scanner
    truncated = T.let(false, T::Boolean)
    logset_count = 0

    begin
      SETS_PER_INTERVAL.times do
        logset_count += 1
        logset = stat_time("find") do
          # S3 logs aren't returned in a consistent order and in some cases
          # won't be returned at all.  However, we don't try to look backwards
          # to find straggling logs as we expect them to be relatively few.
          # So we just parse forwards from the marker, ensuring that we always
          # move ahead.
          scanner.find(marker)
        end

        truncated = logset.truncated?

        stat_gauge "queried_logs", logset.size
        break if logset.size.zero?

        diff_sec = Time.now - T.let(scanner.marker_to_time(marker), Time)
        stat_gauge "marker_offset", (diff_sec / 60).round(1)

        SyncAssetUsageParserJob.perform_later(logset.keys)

        # Save the timestamped key of the last log for which we dispatched
        # a parser job so we can use the key in the next query.
        marker = logset.keys.last
        Asset::SyncStatus.set(:all, marker)

        if truncated
          stat_incr "logset_truncated"
        else
          stat_incr "logset_complete"
          break
        end
      end
    ensure
      stat_gauge "queried_logsets", logset_count
    end
  rescue *RETRYABLE_ERRORS => err
    stat_incr "error_retry"
    raise err
  end

  def log_scanner
    scanner = super
    scanner.max_keys = KEYS_PER_SET
    scanner
  end
end
