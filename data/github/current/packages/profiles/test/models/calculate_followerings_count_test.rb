# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CalculateFolloweringsCountTest < GitHub::TestCase
    test "enqueues job to update follower and following counts once per interval per user" do
      user = create(:user)
      assert_enqueued_jobs 1, only: CalculateFolloweringsCountJob do
        Timecop.freeze do
          user.calculate_followerings_count
          user.calculate_followerings_count # shouldn't enqueue again
        end
      end
    end

    test "records stats that only enqueues 1 follower job for the same user within 10 minutes" do
      Timecop.freeze do
        user = create(:user)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        tag           = "class:calculate_followerings_count_job"
        queued_key    = "job.once_per_interval.queued"
        duplicate_key = "job.once_per_interval.duplicate"

        assert_equal 0, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 0, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count

        user.calculate_followerings_count

        assert_equal 1, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 0, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count

        user.calculate_followerings_count

        assert_equal 1, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 1, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count
      end
    end

    test "records stats that it enqueues follower jobs for different users within 10 minutes" do
      Timecop.freeze do
        user = create(:user)
        other_user = create(:user)
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        tag           = "class:calculate_followerings_count_job"
        queued_key    = "job.once_per_interval.queued"
        duplicate_key = "job.once_per_interval.duplicate"

        assert_equal 0, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 0, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count

        user.calculate_followerings_count

        assert_equal 1, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 0, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count

        other_user.calculate_followerings_count

        assert_equal 2, GitHub.dogstats.increments(queued_key, tags: [tag]).count
        assert_equal 0, GitHub.dogstats.increments(duplicate_key, tags: [tag]).count
      end
    end
  end
end
