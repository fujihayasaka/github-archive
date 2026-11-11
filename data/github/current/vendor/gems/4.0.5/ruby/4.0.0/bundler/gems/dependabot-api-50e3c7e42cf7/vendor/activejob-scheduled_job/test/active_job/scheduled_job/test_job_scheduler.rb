# frozen_string_literal: true

require "test_helper"

class ActiveJob::ScheduledJob::TestJobScheduler < Minitest::Test
  include TestHelpers

  class TestActiveJobSchedulerJob < ActiveJob::Base
    queue_as :example

    class << self
      attr_accessor :enabled, :schedule_options, :performed

      def enabled?
        enabled
      end
    end
  end

  def setup
    @daemon = FakeTimerDaemon.new
    @scheduler = ActiveJob::ScheduledJob::JobScheduler.new(@daemon, ->(_, _) { })
  end

  def test_schedules_enabled_jobs_with_defined_scheduling_options
    TestActiveJobSchedulerJob.enabled = true
    TestActiveJobSchedulerJob.schedule_options = { interval: 1 }
    @scheduler.schedule(TestActiveJobSchedulerJob)

    assert_scheduled TestActiveJobSchedulerJob
  end

  def test_skips_scheduling_disabled_jobs
    TestActiveJobSchedulerJob.enabled = false
    @scheduler.schedule(TestActiveJobSchedulerJob)

    refute_scheduled TestActiveJobSchedulerJob
  end

  def test_skips_scheduling_enabled_jobs_without_scheduling_options
    TestActiveJobSchedulerJob.enabled = true
    TestActiveJobSchedulerJob.schedule_options = nil
    @scheduler.schedule(TestActiveJobSchedulerJob)

    refute_scheduled TestActiveJobSchedulerJob
  end

  private

  def assert_scheduled(job)
    assert_includes @daemon.schedules.keys, job.name
  end

  def refute_scheduled(job)
    assert_empty @daemon.schedules, "unexpected timer scheduled"
  end
end
