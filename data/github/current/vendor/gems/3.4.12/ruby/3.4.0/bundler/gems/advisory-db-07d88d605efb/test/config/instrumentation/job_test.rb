# frozen_string_literal: true

require "test_helper"
require_relative "../../../config/instrumentation/job"

class JobInstrumentationTest < ActionDispatch::IntegrationTest
  class TestJob < ApplicationJob
    retry_on StandardError, queue: :high

    def perform(raise_error)
      raise "Failure" if raise_error
    end
  end

  # It seems like during test runs that active support notifications aren't wired up, so we can't do an "E2E" style test.
  # Instead, we're manually invoking and verifying the expected behavior.

  test "job notifies on error" do
    test_job = TestJob.new(true)
    captured_error = nil
    perform_enqueued_jobs do
      test_job.perform_now
    rescue StandardError => error
      captured_error = error
    end

    AdvisoryDB.stats.expects(:increment).with("active_job.enqueue_error", tags: ["class:job_instrumentation_test/test_job", "queue:high", "adapter:test", "error:runtime_error"])
    AdvisoryDB.stats.expects(:increment).with("active_job.error", tags: ["class:job_instrumentation_test/test_job", "queue:high", "adapter:test", "error:runtime_error", "on:enqueue"])
    ActiveSupport::Notifications.instrument("error.active_job", job: test_job, error: captured_error, on: :enqueue)
  end

  test "job notifies on completion" do
    test_job = TestJob.new(false)
    captured_error = nil
    perform_enqueued_jobs do
      test_job.perform_now
    rescue StandardError => error
      captured_error = error
    end

    expected_tags = ["class:job_instrumentation_test/test_job", "queue:default", "adapter:test"]
    AdvisoryDB.stats.expects(:timing).with("job.time", anything, { tags: expected_tags })
    AdvisoryDB.stats.expects(:gauge).with("job.depth", anything, { tags: expected_tags })
    AdvisoryDB.stats.expects(:increment).with("active_job.performed", tags: expected_tags)
    AdvisoryDB.stats.expects(:distribution).with("active_job.perform.dist.time", anything, tags: expected_tags)

    ActiveSupport::Notifications.instrument("perform.active_job", job: test_job, exception_object: captured_error)
  end

  class RetryableTestJob < TestJob
    retry_on Exception, attempts: 1
  end

  test "job notifies on retry" do
    test_job = RetryableTestJob.new(true)
    captured_error = nil
    perform_enqueued_jobs do
      test_job.perform_now
    rescue StandardError => error
      captured_error = error
    end

    expected_tags = ["class:job_instrumentation_test/retryable_test_job", "queue:default", "adapter:test", "error:runtime_error", "attempt_number:1"]
    AdvisoryDB.stats.expects(:increment).with("active_job.retry", tags: expected_tags)

    ActiveSupport::Notifications.instrument("enqueue_retry.active_job", job: test_job, error: captured_error, wait: 0.seconds)
  end

  test "job notifies on retry exhaustion" do
    test_job = RetryableTestJob.new(true)
    captured_error = nil
    perform_enqueued_jobs do
      test_job.perform_now
    rescue StandardError => error
      captured_error = error
    end

    expected_tags = ["class:job_instrumentation_test/retryable_test_job", "queue:default", "adapter:test", "error:runtime_error"]
    AdvisoryDB.stats.expects(:increment).with("active_job.stop_retry", tags: expected_tags)

    ActiveSupport::Notifications.instrument("retry_stopped.active_job", job: test_job, error: captured_error, wait: 0.seconds)
  end
end
