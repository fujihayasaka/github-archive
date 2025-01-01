# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SlottedCounterIncrementAggregatedJobTest < GitHub::TestCase
  include JobTestHelper

  test "handles dirty exit" do
    assert_retry_on_dirty_exit job: SlottedCounterIncrementAggregatedJob, args: ["ReleaseAsset", 1, { interval: 60, interval_timestamp: 12345 }]
  end

  test "increments counter" do
    assert_equal 0, SlottedCounterService.count_type_and_id("ReleaseAsset", 1)

    enqueue_time = Time.local(2022, 6, 23, 11, 59, 55)
    (1..3).each do |id|
      Timecop.freeze(enqueue_time + id.seconds) do
        SlottedCounterIncrementAggregatedJob.enqueue_aggregated_per_interval(["ReleaseAsset", 1])
      end
    end

    assert_equal 1, enqueued_jobs.size, "should allow to enqueue only once"
    assert_equal(
      ["job:aggregated_per_interval:slotted_counter_increment_aggregated_job:60:27600179:ReleaseAsset:1"],
      GitHub.job_coordination_redis.keys
    )

    perform_enqueued_jobs only: SlottedCounterIncrementAggregatedJob

    assert_equal 0, enqueued_jobs.size, "the queue should be clear"
    assert_equal 3, SlottedCounterService.count_type_and_id("ReleaseAsset", 1)
    assert_equal 0, GitHub.job_coordination_redis.keys.size
  end

  test "not operational if Redis key doesn't exist" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    assert_equal 0, SlottedCounterService.count_type_and_id("ReleaseAsset", 1)

    enqueue_time = Time.local(2022, 6, 23, 11, 59, 55)
    (1..3).each do |id|
      Timecop.freeze(enqueue_time + id.seconds) do
        SlottedCounterIncrementAggregatedJob.enqueue_aggregated_per_interval(["ReleaseAsset", 1])
      end
    end

    assert_equal 1, enqueued_jobs.size, "should allow to enqueue only once"
    assert_equal(
      ["job:aggregated_per_interval:slotted_counter_increment_aggregated_job:60:27600179:ReleaseAsset:1"],
      GitHub.job_coordination_redis.keys
    )

    reset_redis
    SlottedCounterService.expects(:increment_type_and_id).never
    perform_enqueued_jobs only: SlottedCounterIncrementAggregatedJob

    assert_equal 1, GitHub.dogstats.increments("slotted_counter_increment_aggregated_job.aggregated_value.missing").count
    assert_equal 0, enqueued_jobs.size, "the queue should be clear"
    assert_equal 0, SlottedCounterService.count_type_and_id("ReleaseAsset", 1)
    assert_equal 0, GitHub.job_coordination_redis.keys.size
  end

  test "spans two minutes interval" do
    assert_equal 0, SlottedCounterService.count_type_and_id("ReleaseAsset", 1)

    enqueue_time = Time.local(2022, 6, 23, 11, 59, 55)
    (1..5).each do |id|
      Timecop.freeze(enqueue_time + id.seconds) do
        SlottedCounterIncrementAggregatedJob.enqueue_aggregated_per_interval(["ReleaseAsset", 1])
      end
    end

    assert_equal 2, enqueued_jobs.size, "should allow to enqueue twice"
    assert_equal 2, GitHub.job_coordination_redis.keys.size
    assert_includes GitHub.job_coordination_redis.keys, "job:aggregated_per_interval:slotted_counter_increment_aggregated_job:60:27600179:ReleaseAsset:1"
    assert_includes GitHub.job_coordination_redis.keys, "job:aggregated_per_interval:slotted_counter_increment_aggregated_job:60:27600180:ReleaseAsset:1"

    perform_enqueued_jobs only: SlottedCounterIncrementAggregatedJob

    assert_equal 0, enqueued_jobs.size, "the queue should be clear"
    assert_equal 5, SlottedCounterService.count_type_and_id("ReleaseAsset", 1)
    assert_equal 0, GitHub.job_coordination_redis.keys.size
  end

  test "increments counter with custom interval" do
    assert_equal 0, SlottedCounterService.count_type_and_id("ReleaseAsset", 1)

    enqueue_time = Time.local(2022, 6, 23, 11, 59, 55)
    Timecop.freeze(enqueue_time) do
      SlottedCounterIncrementAggregatedJob.enqueue_aggregated_per_interval(["ReleaseAsset", 1], interval: 600)
      SlottedCounterIncrementAggregatedJob.enqueue_aggregated_per_interval(["ReleaseAsset", 1], interval: 600)
      SlottedCounterIncrementAggregatedJob.enqueue_aggregated_per_interval(["ReleaseAsset", 1], interval: 600)
    end

    assert_equal 1, enqueued_jobs.size, "should allow to enqueue only once"
    assert_equal(
      ["job:aggregated_per_interval:slotted_counter_increment_aggregated_job:600:2760017:ReleaseAsset:1"],
      GitHub.job_coordination_redis.keys
    )

    perform_enqueued_jobs only: SlottedCounterIncrementAggregatedJob

    assert_equal 0, enqueued_jobs.size, "the queue should be clear"
    assert_equal 3, SlottedCounterService.count_type_and_id("ReleaseAsset", 1)
    assert_equal 0, GitHub.job_coordination_redis.keys.size
  end

  test "does not reset redis on dirty exit" do
    SlottedCounterIncrementAggregatedJob.any_instance.stubs(:perform).raises(Aqueduct::Worker::JobKilled, "boom")

    enqueue_time = Time.local(2022, 6, 23, 11, 59, 55)
    Timecop.freeze(enqueue_time) do
      SlottedCounterIncrementAggregatedJob.enqueue_aggregated_per_interval(["ReleaseAsset", 1])
      SlottedCounterIncrementAggregatedJob.enqueue_aggregated_per_interval(["ReleaseAsset", 1])
      SlottedCounterIncrementAggregatedJob.enqueue_aggregated_per_interval(["ReleaseAsset", 1])
    end

    assert_equal 1, enqueued_jobs.size, "should allow to enqueue only once"
    assert_equal(
      ["job:aggregated_per_interval:slotted_counter_increment_aggregated_job:60:27600179:ReleaseAsset:1"],
      GitHub.job_coordination_redis.keys
    )

    perform_enqueued_jobs only: SlottedCounterIncrementAggregatedJob

    assert_equal 1, enqueued_jobs.size, "the message should stay in the queue"
    assert_equal 0, SlottedCounterService.count_type_and_id("ReleaseAsset", 1)
    assert_equal(
      ["job:aggregated_per_interval:slotted_counter_increment_aggregated_job:60:27600179:ReleaseAsset:1"],
      GitHub.job_coordination_redis.keys
    )
  end
end
