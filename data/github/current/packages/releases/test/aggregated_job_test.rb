# typed: true
# frozen_string_literal: true

require "test_helper"

class TestAggregatedJob < AggregatedJob
  def perform(id, interval:, interval_timestamp:)
  end
end

class TestAggregatedTwoJob < AggregatedJob
  def perform(id, interval:, interval_timestamp:)
  end
end

class AggregatedJobTest < GitHub::TestCase
  context "enqueue_aggregated_per_interval" do
    test "enqueues only one job per interval" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      assert_enqueued_with(job: TestAggregatedJob, at: 10.minutes.from_now + 10.seconds) do
        Timecop.freeze do
          (1..5).each { |_| TestAggregatedJob.enqueue_aggregated_per_interval([123], interval: 600) }
        end
      end

      assert_equal 1, enqueued_jobs.size
      assert_equal({ job: TestAggregatedJob }, enqueued_jobs[0].slice(:job))

      assert_equal 1, GitHub.dogstats.increments("job.aggregated_per_interval.queued", tags: ["class:#{T.must(TestAggregatedJob.name).underscore}", "interval:600"]).count
      assert_equal 4, GitHub.dogstats.increments("job.aggregated_per_interval.duplicate", tags: ["class:#{T.must(TestAggregatedJob.name).underscore}", "interval:600"]).count

      perform_enqueued_jobs only: TestAggregatedJob
      assert_equal 0, enqueued_jobs.size, "queue should be clear"
      TestAggregatedJob.enqueue_aggregated_per_interval([123], interval: 600)

      assert_equal 1, enqueued_jobs.size
      assert_equal 2, GitHub.dogstats.increments("job.aggregated_per_interval.queued", tags: ["class:#{T.must(TestAggregatedJob.name).underscore}", "interval:600"]).count
    end

    test "same class and job args only enqueue once" do
      Timecop.freeze do
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"])
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"])
      end
      assert_equal 1, enqueued_jobs.count, "only one job should have been queued"
    end

    test "same class and different job args enqueue once each" do
      Timecop.freeze do
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"])
        TestAggregatedJob.enqueue_aggregated_per_interval(["args2"])
      end
      assert_equal 2, enqueued_jobs.count, "both jobs should have been queued"
    end

    test "different class and same job args enqueue once each" do
      Timecop.freeze do
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"])
        TestAggregatedTwoJob.enqueue_aggregated_per_interval(["args"])
      end
      assert_equal 2, enqueued_jobs.count, "both jobs should have been queued"
    end

    test "same class and args but different interval enqueue once each" do
      Timecop.freeze do
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"], interval: 30)
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"], interval: 60)
      end
      assert_equal 2, enqueued_jobs.count, "both jobs should have been queued"
    end

    test "same class and different args enqueue once when same unique id is specified" do
      TestAggregatedJob.stubs(:unique_id).returns("unique_id")

      Timecop.freeze do
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"])
        TestAggregatedJob.enqueue_aggregated_per_interval(["args2"])
      end

      assert_equal 1, enqueued_jobs.count, "only one job should have been queued"
    end

    test "same class and same unique id enqueue once each when different interval specified" do
      Timecop.freeze do
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"], interval: 30)
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"], interval: 60)
      end

      assert_equal 2, enqueued_jobs.count, "both jobs should have been queued"
    end

    test "raises when specifying an interval of zero" do
      assert_raises_with_message ArgumentError, "Interval for AggregatedJob can't be negative or zero" do
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"], interval: 0)
      end

      assert_equal 0, enqueued_jobs.size, "queue should be clear"
    end

    test "raises when specifying a negative interval" do
      assert_raises_with_message ArgumentError, "Interval for AggregatedJob can't be negative or zero" do
        TestAggregatedJob.enqueue_aggregated_per_interval(["args"], interval: -60)
      end

      assert_equal 0, enqueued_jobs.size, "queue should be clear"
    end
  end
end
