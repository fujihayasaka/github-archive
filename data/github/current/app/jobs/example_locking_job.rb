# typed: true
# frozen_string_literal: true

class ExampleLockingJob < ApplicationJob
  queue_as :example_locking

  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: 5.minutes

  def perform(*args)
    # no-op
  end
end
