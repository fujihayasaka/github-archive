# typed: true
# frozen_string_literal: true

require "test_helper"

class WaitForReplicationTest < GitHub::TestCase

  # The example timelines below use seconds as the units for easier
  # visualization for the reader, but the actual implementation in the test code
  # uses tenths (or twentieths) of a second to keep the tests fast.

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  # clock=0: delay=1 - write occurs, job queued
  # clock=1: delay=1 - job starts. time since write t=1, d=1,
  #   --> we know the data's there since d <= t
  test "when current replication delay is lower then the time since last write" do
    Freno.client.stubs(:replication_delay).returns(0.0)
    last_written_at_timestamp = Timestamp.from_time(Time.now - (0.1).seconds)

    w = WaitForReplication.new(last_written_at_timestamp, max_wait_seconds: 0.5, job_name: "MyJob")
    waited = w.wait!

    assert_equal waited, 0
    assert_equal 1, GitHub.dogstats.distributions("wait_for_replication.waited", tags: ["store_name:mysql1", "job_name:MyJob"]).count
    assert_equal 0, GitHub.dogstats.distributions("wait_for_replication.data_unavailable", tags: ["store_name:mysql1"]).count
    assert_equal 0, GitHub.dogstats.distributions("wait_for_replication.waited", tags: ["store_name:mysql1"]).first.value
  end

  # clock=0: delay=2 - write occurs, job queued
  # clock=1: delay=3 - job starts. t = 1, d = 3, wait = 2. sleep 2.
  # clock=2: delay=4 - (sleeping)
  # clock=3: delay=4 - t = 3, d = 4, wait = 1. sleep 1
  # clock=4: delay=3 - t = 4, d = 3, d <= t so the data's there.
  test "waits for replication delay to recover" do
    Freno.client.stubs(:replication_delay).returns(0.2).then.returns(0.3).then.returns(0.2)
    last_written_at_timestamp = Timestamp.from_time(Time.now - (0.1).seconds)

    w = WaitForReplication.new(last_written_at_timestamp, max_wait_seconds: 0.5)
    waited = w.wait!

    assert waited <= 0.3, "Expected waited to be less than or equal to 0.3 but was #{waited}."

    assert_equal 1, GitHub.dogstats.distributions("wait_for_replication.waited", tags: ["store_name:mysql1"]).count
    assert_equal 0, GitHub.dogstats.distributions("wait_for_replication.data_unavailable", tags: ["store_name:mysql1"]).count
    assert_equal waited, GitHub.dogstats.distributions("wait_for_replication.waited", tags: ["store_name:mysql1"]).first.value
  end

  # clock=0: delay=10 - write occurs, job queued
  # clock=1: delay=10 - job starts. t=1, d=10, d - t > max_wait
  #   --> retry later or fall back to primary.
  test "raises an exception if the replication delay is too high to wait at the start" do
    Freno.client.stubs(:replication_delay).returns(1.0)
    last_written_at_timestamp = Timestamp.from_time(Time.now - (0.1).seconds)

    w = WaitForReplication.new(last_written_at_timestamp, max_wait_seconds: 0.5)
    ex = assert_raises(WaitForReplication::DataUnavailable) do
      w.wait!
    end

    assert_match /Cannot wait [0-9]*\.?[0-9]* seconds for replication to catch up on mysql1. Maximum allowed is 0.5 seconds/, ex.message

    assert_equal 0, GitHub.dogstats.distributions("wait_for_replication.waited", tags: ["store_name:mysql1"]).count
    assert_equal 1, GitHub.dogstats.distributions("wait_for_replication.data_unavailable", tags: ["store_name:mysql1"]).count
    assert GitHub.dogstats.distributions("wait_for_replication.data_unavailable", tags: ["store_name:mysql1"]).first.value >= 0.5, "stat for wait_for_replication.data_unavailable should be higher than max_wait_seconds"
  end

  # clock=0: delay=2 - write occurs, job queued
  # clock=1: delay=3 - job starts. t = 1, d = 3, wait = 2. sleep 2.
  # clock=2: delay=4 - (sleeping)
  # clock=3: delay=5 - t = 3, d = 5, wait = 2. sleep 2. <-- this is why we check again
  # clock=4: delay=6 - (sleeping)
  # clock=5: delay=7 - t = 5, d = 7, wait = 2
  #   --> this would push us past max_wait, so retry later or fall back to primary
  test "raises an exception if replication delay doesn't recover in time" do
    # Freeze time, otherwise the clock may advance beyond the 0.3s replication delay before
    # we check it in #wait!
    Timecop.freeze do
      Freno.client.stubs(:replication_delay).returns(0.2).then.returns(0.4).then.returns(0.6)
      last_written_at_timestamp = Timestamp.from_time(Time.now - (0.1).seconds)

      w = WaitForReplication.new(last_written_at_timestamp, max_wait_seconds: 0.5)
      ex = assert_raises(WaitForReplication::DataUnavailable) do
        w.wait!
      end

      assert_match /Cannot wait [0-9]*\.?[0-9]* seconds for replication to catch up on mysql1. Maximum allowed is 0.5 seconds/, ex.message

      assert_equal 1, GitHub.dogstats.distributions("wait_for_replication.waited", tags: ["store_name:mysql1"]).count
      assert_equal 1, GitHub.dogstats.distributions("wait_for_replication.data_unavailable", tags: ["store_name:mysql1"]).count
      assert GitHub.dogstats.distributions("wait_for_replication.data_unavailable", tags: ["store_name:mysql1"]).first.value >= 0.5, "stat for wait_for_replication.data_unavailable should be higher than max_wait_seconds"
      assert_in_delta 0.4, GitHub.dogstats.distributions("wait_for_replication.waited", tags: ["store_name:mysql1"]).first.value, 0.1
    end
  end

  # clock=0: delay=2 - write occurs, job queued
  # clock=1: delay=3 - job starts. t = 1, d = 3, wait = 2. sleep 2.
  # clock=2: delay=1 - (sleeping, but delay has recovered)
  # clock=3: delay=1 - t = 3, d = 1, d <= t so data's there
  test "sleeps longer than necessary if replication delay recovers quickly" do
    Timecop.freeze do
      Freno.client.stubs(:replication_delay).returns(0.2).then.returns(0.0)
      last_written_at_timestamp = Timestamp.from_time(Time.now - (0.1).seconds)

      w = WaitForReplication.new(last_written_at_timestamp, max_wait_seconds: 0.5)
      waited = w.wait!

      assert_in_delta 0.2, waited, 0.1
    end
  end

  test "accepts hash of gtids" do
    Timecop.freeze do
      Freno.client.stubs(:replication_delay).returns(0.2)

      last_written_at_timestamp = Timestamp.from_time(Time.now - (0.1).seconds)
      gtids = { mysql1: { gtid: fake_gtid, time: last_written_at_timestamp } }

      w = WaitForReplication.new(gtids, max_wait_seconds: 0.5)
      waited = w.wait!

      assert_in_delta 0.2, waited, 0.01
    end
  end

  test "accepts hash with multiple clusters" do
    Timecop.freeze do
      mysql1_timestamp = Timestamp.from_time((0.3).seconds.ago)
      repositories_timestamp = Timestamp.from_time((0.1).seconds.ago)
      gtids = {
        mysql1: { gtid: fake_gtid, time: mysql1_timestamp },
        repositories: { gtid: fake_gtid, time: repositories_timestamp }
      }

      w = WaitForReplication.new(gtids, max_wait_seconds: 0.5)
      w.stubs(:replication_wait_for_cluster).with(:mysql1).returns(0.5)
      w.stubs(:replication_wait_for_cluster).with(:repositories).returns(0.4)
      waited = w.wait!

      # Should wait for the longest duration of clusters
      # mysql1: 0.5 - 0.2 = 0.2
      # repositories: 0.4 - 0.1 = 0.3

      assert_in_delta 0.3, waited, 0.01
    end
  end unless GitHub.enterprise?

  test "immediately returns if the replication state is empty" do
    Timecop.freeze do
      w = WaitForReplication.new(Hash.new)
      w.expects(:sleep).never

      assert_equal 0, w.wait!
    end
  end

  test "waits if freno errors" do
    Timecop.freeze do
      Freno.client.stubs(:replication_delay).raises(Freno::Error.new).then.returns(0)
      last_written_at_timestamp = Timestamp.from_time(Time.now)

      w = WaitForReplication.new(last_written_at_timestamp, max_wait_seconds: 3, default_wait_time: 1)
      waited = w.wait!

      assert_in_delta 1, waited, 0.1
    end
  end

  test "reads wait time from cluster class" do
    Timecop.freeze do
      ApplicationRecord::IssuesPullRequests.stubs(:default_replication_wait!).returns(777.7)
      last_written_at_timestamp = Timestamp.from_time(Time.now - (0.1).seconds)

      w = WaitForReplication.new({ "issues-pull-requests": { time: last_written_at_timestamp } }, max_wait_seconds: 1)
      waited = w.wait!

      assert_in_delta 0.7, waited, 0.1
    end
  end if GitHub.flipper[:wait_for_replication_source].enabled?

  test "includes the worker pool in the stats when relevant" do
    # Freeze time, otherwise the clock may advance beyond the 0.3s replication delay before
    # we check it in #wait!
    Timecop.freeze do
      Freno.client.stubs(:replication_delay).returns(0.2).then.returns(0.4).then.returns(0.6)
      last_written_at_timestamp = Timestamp.from_time(Time.now - (0.1).seconds)

      Aqueduct::Worker.config.worker_pool = "test-pool"

      w = WaitForReplication.new(last_written_at_timestamp, max_wait_seconds: 0.5)
      ex = assert_raises(WaitForReplication::DataUnavailable) do
        w.wait!
      end

      assert_equal 1, GitHub.dogstats.distributions("wait_for_replication.waited", tags: ["store_name:mysql1", "worker_pool:test-pool"]).count
      assert_equal 1, GitHub.dogstats.distributions("wait_for_replication.data_unavailable", tags: ["store_name:mysql1", "worker_pool:test-pool"]).count
    end
  end

  def fake_gtid
    "00000000-0000-0000-0000-000000000000:1"
  end
end
