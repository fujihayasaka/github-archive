# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TestJob < ApplicationJob
  queue_as :test

  # The Hello World of background jobs.
  #
  # To queue up one of these:
  #
  #     TestJob.perform_later
  #
  # To make it run for a different length of time (default is 1.0 seconds):
  #
  #     TestJob.perform_later(duration: 3.0)
  #
  # To allocate a 30M string to emulate memory use:
  #
  #     TestJob.perform_later(duration: 3.0, alloc: 30 * 1024 * 1024)
  #
  # To put it on a different queue:
  #
  #     TestJob.set(queue: :a_different_queue).perform_later
  #
  # To queue up a bunch:
  #
  #     10.times { TestJob.perform_later }
  def perform(duration: 1.0, alloc: 0, should_raise: false, should_write: false)
    GitHub.logger.info("gh.test_job.duration" => duration, "gh.test_job.alloc" => alloc, "gh.test_job.should_raise" => should_raise, "gh.test_job.should_write" => should_write)
    # Test the database connection
    User.count
    # Test writes
    with_write { User.last&.touch } if should_write
    # Test the redis connection
    GitHub.job_coordination_redis.exists("test:key")
    # Allocate some RES mem before sleeping
    string = "x" * alloc
    # Take up space in workers
    sleep(duration)

    # Blow up if we were asked to.
    raise "kaboom" if should_raise
  end
end
