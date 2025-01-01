# frozen_string_literal: true

class ReplicationLagInstrumentationJob < ApplicationJob
  queue_as :low

  # Max number of timestamps to process should <= AdvisorySyncState::BATCH_SIZE
  def perform(pushed_at:, published_at_timestamps:, batch_size:, total_batches:)
    replication_durations = []
    published_at_timestamps.each do |published_at|
      replication_duration = pushed_at - published_at
      duration_ms = (replication_duration * 1_000).round
      replication_durations << duration_ms
      AdvisoryDB.stats.distribution(
        "advisory-database.push_advisories_to_repo_job.replication_lag.duration_ms",
        duration_ms,
      )
    end

    min_duration = replication_durations.min
    max_duration = replication_durations.max
    median_duration = replication_durations.sort[replication_durations.size / 2]
    ::GitHub::Telemetry::Logs.logger.info(
      "Replication lag stats for advisories",
      "gh.advisory_inbox.replication_lag.batch_size": published_at_timestamps.size,
      "gh.advisory_inbox.replication_lag.total_batches": total_batches,
      "gh.advisory_inbox.replication_lag.duration_ms.min": min_duration,
      "gh.advisory_inbox.replication_lag.duration_ms.max": max_duration,
      "gh.advisory_inbox.replication_lag.duration_ms.median": median_duration,
    )
  end
end
