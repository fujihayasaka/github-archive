# typed: true
# frozen_string_literal: true

require "test_helper"

class JobSchedulerTest < GitHub::TestCase
  include HydroTestHelpers

  class TestActiveJobSchedulerJob < ApplicationJob
    queue_as :example

    class << self
      attr_accessor :enabled, :schedule_options, :performed
    end

    def self.enabled?
      enabled
    end
  end

  class TestTimerDaemon
    attr_reader :interval

    def schedule(_job, interval, _options = {})
      @interval = interval
      yield
    end

    def log(*args); end
  end

  setup do
    @output = StringIO.new
    @daemon = TestTimerDaemon.new
    @scheduler = JobScheduler.new(@daemon)
  end

  test "schedules enabled jobs with defined scheduling options" do
    interval = Faker::Number.within(range: 1..1000)
    TestActiveJobSchedulerJob.enabled = true
    TestActiveJobSchedulerJob.schedule_options = { interval: interval }

    assert_enqueued_jobs(1, only: TestActiveJobSchedulerJob) do
      @scheduler.schedule(TestActiveJobSchedulerJob)
    end
    assert_interval(interval)
  end

  test "skips scheduling disabled jobs" do
    TestActiveJobSchedulerJob.enabled = false

    assert_no_enqueued_jobs do
      @scheduler.schedule(TestActiveJobSchedulerJob)
    end
  end

  test "skips scheduling enabled jobs without scheduling options" do
    TestActiveJobSchedulerJob.enabled = true
    TestActiveJobSchedulerJob.schedule_options = nil

    assert_no_enqueued_jobs do
      @scheduler.schedule(TestActiveJobSchedulerJob)
    end
  end

  context "scheduling with class name" do
    test "schedules enabled jobs with defined scheduling options" do
      interval = Faker::Number.within(range: 1..1000)
      schedule_options = { interval: interval, condition: -> { true } }

      assert_enqueued_with(job: JobEnqueuingProxyJob, args: ["JobSchedulerTest::TestActiveJobSchedulerJob"]) do
        @scheduler.schedule("JobSchedulerTest::TestActiveJobSchedulerJob", schedule_options)
      end
      assert_interval(interval)
    end

    test "skips scheduling disabled jobs" do
      schedule_options = { interval: 1, condition: -> { false } }

      assert_no_enqueued_jobs do
        @scheduler.schedule("JobSchedulerTest::TestActiveJobSchedulerJob", schedule_options)
      end
    end

    test "skips scheduling enabled jobs without scheduling options" do
      @scheduler.schedule("JobSchedulerTest::TestActiveJobSchedulerJob")

      assert_no_enqueued_jobs do
        @scheduler.schedule("JobSchedulerTest::TestActiveJobSchedulerJob")
      end
    end
  end

  def assert_interval(interval)
    assert_equal interval, @daemon.interval
  end
end
