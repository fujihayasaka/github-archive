# typed: true
# frozen_string_literal: true

require "test_helper"

class LastAccessibleTest < GitHub::TestCase
  fixtures do
    @access = create(:user_programmatic_access)

    cache_key_suffix = Digest::SHA256.hexdigest("user_programmatic_access:#{@access.id}")
    @cache_key = "last_accessed:#{cache_key_suffix}"
  end

  test "#access_throttling is one week" do
    Timecop.freeze do
      assert_equal 1.week, @access.access_throttling
    end
  end

  context "#bumped_within_throttling_period?" do
    test "returns false if accessed_at is nil" do
      assert_nil @access.accessed_at
      refute_predicate @access, :bumped_within_throttling_period?
    end

    test "true if bumped within the throttling threshold" do
      Timecop.freeze do
        @access.update!(accessed_at: 1.day.ago); @access.reload
        assert_predicate @access, :bumped_within_throttling_period?
      end
    end

    test "false if bumped outside the throttling threshold" do
      Timecop.freeze do
        accessed_at = (@access.access_throttling + 2.days).ago

        @access.update!(accessed_at: accessed_at); @access.reload
        refute_predicate @access, :bumped_within_throttling_period?
      end
    end
  end

  context "#bump" do
    test "enqueues a job to update the timestamp" do
      assert_nil @access.accessed_at

      with_cache_enabled do
        Timecop.freeze do
          assert_enqueued_with(job: ProgrammaticAccessBumpJob, args: [@access, Time.zone.now]) do
            @access.bump
          end

          refute_nil GitHub.cache.get(@cache_key)
        end
      end
    end

    test "does not enqueue a job if bumped within the throttling period" do
      with_cache_enabled do
        Timecop.freeze do
          @access.update!(accessed_at: 2.days.ago); @access.reload
          assert_predicate @access, :bumped_within_throttling_period?

          assert_no_enqueued_jobs { @access.bump }
          assert_nil GitHub.cache.get(@cache_key)
        end
      end
    end

    test "does not enqueue a job if there is a memcached lock" do
      with_cache_enabled do
        Timecop.freeze do
          GitHub.cache.add(@cache_key, Time.zone.now, 1.week.to_i)

          assert_nil @access.accessed_at
          assert_no_enqueued_jobs { @access.bump }
        end
      end
    end
  end

  context "#bump!" do
    test "updates the timestamp" do
      Timecop.freeze do
        now = Time.zone.now
        @access.bump!(now); @access.reload

        assert_equal now.to_i, @access.accessed_at.to_i
      end
    end

    test "does not update the timestamp if it has been bumped within the throttling period" do
      error_time = Time.iso8601("2022-11-08T01:04:59Z")
      Timecop.freeze(error_time) do
        earlier = 2.days.ago
        now     = Time.zone.now

        @access.update!(accessed_at: earlier); @access.reload
        assert_predicate @access, :bumped_within_throttling_period?

        @access.bump!(now); @access.reload
        assert_equal earlier.to_i, @access.accessed_at.to_i
      end
    end
  end
end
