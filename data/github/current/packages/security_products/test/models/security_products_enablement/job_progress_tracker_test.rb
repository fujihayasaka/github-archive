# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class JobProgressTrackerTest < GitHub::TestCase
    include DogstatsTestHelpers

    DATADOG_PREFIX = "security_products_enablement.job_progress_tracker"

    def tracker
      @tracker ||= JobProgressTracker.new(123)
    end

    test "#start marks the tracker as in progress" do
      assert_changes -> { tracker.in_progress? }, from: false, to: true do
        assert_equal true, tracker.start
      end

      assert_dogstats_increment(1, "#{DATADOG_PREFIX}.start", tags: ["started:true"])
    end

    test "#start deletes the existing remaining and total job counters if the tracker is started" do
      redis = GitHub.job_coordination_redis
      remaining_jobs_key = tracker.instance_variable_get(:@remaining_jobs_key)
      total_jobs_key = tracker.instance_variable_get(:@total_jobs_key)

      redis.set(remaining_jobs_key, 1)
      redis.set(total_jobs_key, 25)

      assert_equal "1", redis.get(remaining_jobs_key)
      assert_equal "25", redis.get(total_jobs_key)

      assert_changes -> { tracker.in_progress? }, from: false, to: true do
        assert_equal true, tracker.start
      end

      assert_nil redis.get(remaining_jobs_key)
      assert_nil redis.get(total_jobs_key)
    end

    test "#start returns false if the tracker is already in progress" do
      tracker.start
      tracker.increment_jobs

      assert_no_changes -> { tracker.in_progress? }, from: true do
        assert_equal false, tracker.start
      end

      # Counters are not reset.
      assert_equal 2, tracker.increment_jobs
      assert_equal 1, tracker.decrement_jobs

      assert_dogstats_increment(1, "#{DATADOG_PREFIX}.start", tags: ["started:false"])
    end

    test "#increment_jobs returns the total job count and #decrement_jobs returns the remaining job count" do
      tracker.start

      assert_equal 1, tracker.increment_jobs
      assert_equal 2, tracker.increment_jobs
      assert_equal 1, tracker.decrement_jobs
      assert_equal 3, tracker.increment_jobs
      assert_equal 1, tracker.decrement_jobs
      assert_equal 0, tracker.decrement_jobs

      assert_dogstats_increment(3, "#{DATADOG_PREFIX}.increment_jobs")
      assert_dogstats_increment(2, "#{DATADOG_PREFIX}.decrement_jobs", tags: ["finished:false"])
      assert_dogstats_increment(1, "#{DATADOG_PREFIX}.decrement_jobs", tags: ["finished:true"])
    end

    test "#increment_jobs extends the expiry date for keys" do
      redis_client = GitHub.job_coordination_redis
      redis_client.stubs(:expire).times(3)
      tracker.stubs(:redis).returns(redis_client)

      tracker.start
      tracker.increment_jobs
    end

    test "#decrement_jobs extends expiry date for keys" do
      redis_client = GitHub.job_coordination_redis
      redis_client.stubs(:expire).times(3)
      tracker.stubs(:redis).returns(redis_client)

      tracker.start
      tracker.decrement_jobs
    end

    test "#finish marks the tracker as not in progress and returns total jobs" do
      tracker.start
      3.times { tracker.increment_jobs }
      3.times { tracker.decrement_jobs }

      assert_changes -> { tracker.in_progress? }, from: true, to: false do
        assert_equal 3, tracker.finish
      end

      assert_dogstats_increment(1, "#{DATADOG_PREFIX}.finish")
    end

    test "#finish tracks throughput if work was done" do
      Timecop.freeze do
        tracker.start
        100.times { tracker.increment_jobs }
        100.times { tracker.decrement_jobs }
        Timecop.freeze(2.seconds)

        assert_equal 100, tracker.finish

        assert_dogstats_distribution_value(50, "#{DATADOG_PREFIX}.throughput", tags: ["magnitude:2"])
      end
    end

    test "#finish doesn't track throughput if no work was done" do
      Timecop.freeze do
        tracker.start
        Timecop.freeze(2.seconds)

        assert_equal 0, tracker.finish

        refute_dogstats_distribution("#{DATADOG_PREFIX}.throughput")
      end
    end

    test "#finish tracks total jobs if work was done" do
      tracker.start
      100.times { tracker.increment_jobs }
      100.times { tracker.decrement_jobs }

      assert_equal 100, tracker.finish

      assert_dogstats_distribution_value(100, "#{DATADOG_PREFIX}.total_jobs")
    end

    test "#finish doesn't track total jobs if no work was done" do
      tracker.start

      assert_equal 0, tracker.finish

      refute_dogstats_distribution("#{DATADOG_PREFIX}.total_jobs")
    end
  end
end
