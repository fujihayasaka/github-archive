# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class GistMaintenanceSchedulerJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include JobTestHelper

  fixtures do
    @gist = GistHelpers.generate(
      contents: [{ name: "1", value: "random content" }],
      last_maintenance_at: (GistMaintenanceSchedulerJob::MIN_AGE + 3.hours).ago,
      pushed_count_since_maintenance: 1
    )
  end

  test "scheduled to run every 2 minutes" do
    assert_equal GistMaintenanceSchedulerJob.schedule_options[:interval], 2.minutes
  end

  test "schedules maintenance jobs" do
    assert_enqueued_jobs 1, queue: @gist.maintenance_queue_name.value! do
      GistMaintenanceSchedulerJob.perform_now
    end
  end

  test "updates gist 'action:maint' histograms" do
    GistMaintenanceSchedulerJob.perform_now
    assert_dogstats_histogram "gist", tags: ["action:maint", "type:lag"]
    assert_dogstats_histogram "gist", tags: ["action:maint", "type:most_active"]
  end

  test "counts gists" do
    GistMaintenanceSchedulerJob.perform_now
    assert_dogstats_gauge_value 1, "git_maintenance.count", tags: ["type:gist", "status:scheduled"]
    assert_dogstats_gauge_value 0, "git_maintenance.count", tags: ["type:gist", "status:retry"]
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit(job: GistMaintenanceSchedulerJob)
  end
end
