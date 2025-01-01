# typed: true
# frozen_string_literal: true

require "test_helper"

class GistMaintenanceJobTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @owner = create(:user, name: "mrowner", plan: "medium")
    @gist = GistHelpers.generate contents: [{ name: "1", value: "random content" }],
      user: @owner
  end

  setup do
    GitHub.realtime_backups_enabled = true
  end

  teardown do
    GitHub.realtime_backups_enabled = false
    FileUtils.rm_f(GitHub::Enterprise.backup_in_progress_file)
  end

  def perform_gist_maintenance(gist)
    GistMaintenanceJob.perform_now(gist.id)
  end

  test "performing maintenance" do
    last_run = 1.hour.ago
    @gist.last_maintenance_at = last_run
    @gist.save!
    perform_gist_maintenance(@gist)
    @gist.reload
    assert @gist.last_maintenance_at > last_run
  end

  if GitHub.enterprise?
    test "requeues when backup in progress" do
      GistMaintenanceJob.any_instance.expects(:sleep).with(60)
      FileUtils.mkdir_p File.dirname(GitHub::Enterprise.backup_in_progress_file)
      FileUtils.touch GitHub::Enterprise.backup_in_progress_file

      Gist.any_instance.expects(:perform_maintenance).never
      assert_enqueued_with job: GistMaintenanceJob, queue: @gist.maintenance_queue_name.value! do
        assert_logged(Body: "Gist maintenance delayed due to backup in progress") do
          perform_gist_maintenance(@gist)
        end
      end
    end
  end
end
