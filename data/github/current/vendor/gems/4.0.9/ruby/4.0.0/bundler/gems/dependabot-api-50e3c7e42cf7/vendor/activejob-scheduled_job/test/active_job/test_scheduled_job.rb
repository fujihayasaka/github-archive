# frozen_string_literal: true

require "test_helper"

class ActiveJob::TestScheduledJob < Minitest::Test
  include TestHelpers

  class TestJob < ActiveJob::Base
    include ActiveJob::ScheduledJob::Base
    queue_as :example

    schedule interval: 1.minute
  end

  class HostScopeTestJob < ActiveJob::Base
    include ActiveJob::ScheduledJob::Base
    queue_as :example

    schedule interval: 1.minute, scope: :host
  end

  class DisabledTestJob < ActiveJob::Base
    include ActiveJob::ScheduledJob::Base
    queue_as :example

    schedule interval: 1.minute, condition:-> { false }
  end

  def setup
    @daemon = FakeTimerDaemon.new
    ActiveJob::ScheduledJob.reset_config!
  end

  def test_jobs_are_scheduled
    ActiveJob::ScheduledJob.configure do |config|
      config.timer_daemon = @daemon
      config.scheduled_jobs = [TestJob]
    end

    assert_equal @daemon.schedules["ActiveJob::TestScheduledJob::TestJob"], [1.minute.to_i, scope: :global]
  end

  def test_jobs_are_scheduled_with_host_scope
    ActiveJob::ScheduledJob.configure do |config|
      config.timer_daemon = @daemon
      config.scheduled_jobs = [HostScopeTestJob]
    end

    assert_equal @daemon.schedules["ActiveJob::TestScheduledJob::HostScopeTestJob"], [1.minute.to_i, scope: :host]
  end

  def test_jobs_are_not_scheduled_if_disabled
    ActiveJob::ScheduledJob.configure do |config|
      config.timer_daemon = @daemon
      config.scheduled_jobs = [DisabledTestJob]
    end

    assert_empty @daemon.schedules
  end

  def test_errors_are_reported
    @error = "test"
    @daemon.raise_on_schedule = true
    ActiveJob::ScheduledJob.configure do |config|
      config.timer_daemon = @daemon
      config.error_reporter = ->(error, opts = {}) { @error = error }
      config.scheduled_jobs = [TestJob]
    end

    assert_equal @error.message, "FakeTimerDaemon#schedule raised"
  end
end
