# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::SharedStorage
  class ArtifactEventAggregationStartTest < GitHub::TestCase
    KV_KEY = "billing.shared_storage.artifact_event_aggregation.next_run"

    setup do
      Billing::Kv.store.del(KV_KEY)
      @default_fan_args = [{ fan_index: 0, fan_total: ArtifactEventAggregationStart.concurrent_fans }]
    end

    test "enqueues a FanoutAggregationJob for the current hour into concurrent runs" do
      next_run = Time.new(2019, 10, 1, 12, 0, 0)
      start_aggregation_at = Time.new(2019, 10, 1, 12, 15, 0)

      Billing::Kv.store.set(KV_KEY, next_run.to_i.to_s)

      Timecop.freeze(start_aggregation_at) do
        ArtifactEventAggregationStart.new.perform
        0.upto(ArtifactEventAggregationStart.concurrent_fans - 1).each do |i|
          assert_enqueued_with(job: FanoutAggregationJob, args: [next_run, fan_index: i, fan_total: ArtifactEventAggregationStart.concurrent_fans])
        end
      end
    end

    test "enqueues FanoutAggregationJobs for missed hours" do
      disable_feature_flag(:billing_large_event_windows)
      ten_am_run = Time.new(2019, 10, 1, 10, 0, 0)
      eleven_am_run = Time.new(2019, 10, 1, 11, 0, 0)
      noon_run = Time.new(2019, 10, 1, 12, 0, 0)

      start_aggregation_at = Time.new(2019, 10, 1, 12, 15, 0)

      Billing::Kv.store.set(KV_KEY, ten_am_run.to_i.to_s)

      Timecop.freeze(start_aggregation_at) do
        assert_enqueued_with(job: FanoutAggregationJob, args: [ten_am_run] + @default_fan_args) do
          assert_enqueued_with(job: FanoutAggregationJob, args: [eleven_am_run] + @default_fan_args) do
            assert_enqueued_with(job: FanoutAggregationJob, args: [noon_run] + @default_fan_args) do
              ArtifactEventAggregationStart.new.perform
            end
          end
        end
      end

      new_next_run_timestamp = Billing::Kv.store.get(KV_KEY).value!.to_i
      assert_equal noon_run + 1.hour, Time.at(new_next_run_timestamp)
    end

    test "does nothing if the next run time is in the future" do
      next_run = Time.new(2019, 10, 1, 13, 0, 0)
      start_aggregation_at = Time.new(2019, 10, 1, 12, 15, 0)

      Billing::Kv.store.set(KV_KEY, next_run.to_i.to_s)

      Timecop.freeze(start_aggregation_at) do
        assert_no_enqueued_jobs(only: FanoutAggregationJob) do
          ArtifactEventAggregationStart.new.perform
        end
      end

      new_next_run_timestamp = Billing::Kv.store.get(KV_KEY).value!.to_i
      assert_equal next_run, Time.at(new_next_run_timestamp)
    end

    test "handles when the next run time is missing from KV" do
      disable_feature_flag(:billing_large_event_windows)
      next_run = Time.new(2019, 10, 1, 12, 0, 0)
      start_aggregation_at = Time.new(2019, 10, 1, 12, 15, 0)

      Timecop.freeze(start_aggregation_at) do
        assert_enqueued_with(job: FanoutAggregationJob, args: [next_run] + @default_fan_args) do
          ArtifactEventAggregationStart.new.perform
        end
      end

      new_next_run_timestamp = Billing::Kv.store.get(KV_KEY).value!.to_i
      assert_equal next_run + 1.hour, Time.at(new_next_run_timestamp)
    end

    test "does not enqueue the fanout job if KV becomes unavailable to write" do
      next_run = Time.new(2019, 10, 1, 12, 0, 0)
      start_aggregation_at = Time.new(2019, 10, 1, 12, 15, 0)

      Billing::Kv.store.set(KV_KEY, next_run.to_i.to_s)

      Billing::Kv.store.stubs(:set).raises(GitHub::KV::UnavailableError)

      travel_to(start_aggregation_at) do
        assert_no_enqueued_jobs(only: FanoutAggregationJob) do
          ArtifactEventAggregationStart.new.perform
        end
      end

      next_run_timestamp = Billing::Kv.store.get(KV_KEY).value!.to_i
      assert_equal next_run, Time.at(next_run_timestamp)
    end
  end
end if GitHub.billing_enabled?
