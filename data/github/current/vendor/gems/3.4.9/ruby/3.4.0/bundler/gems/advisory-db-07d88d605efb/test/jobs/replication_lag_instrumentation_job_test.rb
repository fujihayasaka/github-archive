# frozen_string_literal: true

require "test_helper"

class ReplicationLagInstrumentationJobTest < ActiveJob::TestCase
  setup do
    @published_at_1 = Time.new(2022, 1, 12).utc
    @published_at_2 = Time.new(2023, 2, 14).utc
    @published_at_timestamps = [@published_at_1, @published_at_2]

    AdvisoryDB.stats.stubs(:distribution)
  end

  test "instruments replication lag stats for each published_at timestamp" do
    Timecop.freeze do
      now = Time.current
      lag_1 = ((now - @published_at_1) * 1_000).round
      lag_2 = ((now - @published_at_2) * 1_000).round
      AdvisoryDB.stats.expects(:distribution).once.with("advisory-database.push_advisories_to_repo_job.replication_lag.duration_ms", lag_1)
      AdvisoryDB.stats.expects(:distribution).once.with("advisory-database.push_advisories_to_repo_job.replication_lag.duration_ms", lag_2)

      ReplicationLagInstrumentationJob.perform_now(
        pushed_at: now,
        published_at_timestamps: @published_at_timestamps,
        batch_size: 2,
        total_batches: 1,
      )
    end
  end
end
