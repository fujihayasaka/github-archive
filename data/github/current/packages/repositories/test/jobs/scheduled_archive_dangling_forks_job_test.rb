# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ScheduledArchiveDanglingForksJobTest < GitHub::TestCase
  include JobTestHelper

  test "scheduled to run once a day" do
    assert_equal ScheduledArchiveDanglingForksJob.schedule_options[:interval], 24.hours
  end

  test "enqueues ArchiveDanglingForksJob on dotcom; no-op in GHE" do
    if GitHub.enterprise?
      refute ScheduledArchiveDanglingForksJob.enabled?
      ScheduledArchiveDanglingForksJob.perform_now
      assert_enqueued_jobs 0, only: ArchiveDanglingForksJob, queue: :archive_dangling_forks
    else
      assert ScheduledArchiveDanglingForksJob.enabled?
      ScheduledArchiveDanglingForksJob.perform_now
      assert_enqueued_jobs 1, only: ArchiveDanglingForksJob, queue: :archive_dangling_forks
    end
  end

  test "enqueues ArchiveDanglingForksJob with correct arguments" do
    skip if GitHub.enterprise?

    # The scheduled job enqueues the ArchiveDanglingForks job with no arguments
    ArchiveDanglingForksJob.expects(:perform_later).with(any_parameters).never
    ArchiveDanglingForksJob.expects(:perform_later).once

    ScheduledArchiveDanglingForksJob.perform_now
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: ScheduledArchiveDanglingForksJob
  end
end
