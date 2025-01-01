# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class BatchedJobThrottlerTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers
    include DogstatsTestHelpers

    class TestJob < BatchedJob
      include BatchedJobThrottler
    end

    test "job enqueued with delay" do
      Kernel.stubs(:rand).returns(0.5)
      expected_wait = 1.0 + 0.5 * 1.0 * 1.0

      now = Time.now.utc
      Timecop.freeze(now) do
        assert_nothing_raised do
          queued_job = TestJob.perform_later(owner_id: 1)
          assert_equal expected_wait.seconds.from_now, queued_job.scheduled_at
        end
      end

      assert_dogstats_distribution 1, "security_center.batched_job_throttler.wait_with_jitter.dist"
    end

    test "job delay can be adjust with flags" do
      wait_factor_flag = "security_center_test_job_wait_between_batches_factor"
      GitHub.flipper[wait_factor_flag].enable_percentage_of_actors(2)

      jitter_flag = "security_center_test_job_wait_jitter"
      GitHub.flipper[jitter_flag].enable_percentage_of_actors(0.5)

      Kernel.stubs(:rand).returns(0.5)
      expected_wait = 2.0 + 0.5 * 2.0 * 0.5

      now = Time.now.utc
      Timecop.freeze(now) do
        assert_nothing_raised do
          queued_job = TestJob.perform_later(owner_id: 1)
          assert_equal expected_wait.seconds.from_now, queued_job.scheduled_at
        end
      end
    end
  end
end
