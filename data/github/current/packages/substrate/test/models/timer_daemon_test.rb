# typed: false
# frozen_string_literal: true

require "test_helper"
require "timer_daemon"

class TimerDaemonTest < Minitest::Test
  def setup
    redis = GitHub.job_coordination_redis
    null_logger = -> (*_, **) {}

    redis.flushdb

    @daemon = TimerDaemon.new(redis, null_logger)
  end

  def test_scheduling_a_timer
    called = false
    @daemon.schedule("test", 1) { called = true }
    @daemon.run! 1.0
    assert called, "block should be called"
  end

  def test_scheduling_multiple_timers
    timer1_count = 0
    @daemon.schedule("timer1", 1)    { timer1_count += 1 }

    timer2_count = 0
    @daemon.schedule("timer2", 3)    { timer2_count += 1 }

    timer3_count = 0
    @daemon.schedule("timer3", 1000) { timer3_count += 1 }

    @daemon.run! 5.0
    assert timer1_count >= 5.0
    assert_equal 2, timer2_count
    assert_equal 1, timer3_count
  end

  def test_schedule_validates_interval
    assert_raises TimerDaemon::IntervalTooSmallError do
      @daemon.schedule("test", 0.5)
    end

    assert_raises TimerDaemon::IntervalTooSmallError do
      @daemon.schedule("test", 0)
    end
  end

  def test_error_handlers
    error1_count = 0
    error2_count = 0
    @daemon.error { |_boom, _timer| error1_count = 1 }
    @daemon.error do |_boom, timer|
      error2_count = 1
      assert_equal "fail", timer.name
    end
    @daemon.schedule("fail", 1) { fail "test" }
    @daemon.run! 6

    assert_equal 1, error1_count
    assert_equal 1, error2_count
  end
end
