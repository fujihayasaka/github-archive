# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::AttachmentsMaintenanceJobTest < GitHub::TestCase
  include UploadableTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    enable_feature_flag(:github_models_attachments_maintenance_job)
    @user = create(:user)
  end

  sig { void }
  def perform_cleanup_flow_entirely
    perform_enqueued_jobs(only: [
      GitHubModels::AttachmentsCleanupJob,
      GitHubModels::AttachmentsMaintenanceJob
    ]) do
      GitHubModels::AttachmentsMaintenanceJob.perform_now
    end
  end

  test "when feature flag is disabled the job does not run" do
    disable_feature_flag(:github_models_attachments_maintenance_job)

    assert_logged(
      Body: "Skipping GitHubModels::AttachmentsMaintenanceJob",
      "gh.github_models.flag_enabled": false,
    ) do
      perform_cleanup_flow_entirely
    end
  end

  test "deletes attachments older than 1 week" do
    travel_to(20.days.ago) do
      save_file_for_uploadable(GitHubModels::Attachment.new(uploader: @user))
      save_file_for_uploadable(GitHubModels::Attachment.new(uploader: @user))
    end

    assert_equal(2, GitHubModels::Attachment.count)

    assert_logged(
      Body: "Deleting stale github models attachments",
      "gh.github_models.attachments.destroy_count": 2,
    ) do
      assert_difference("GitHubModels::Attachment.count", -2) do
        perform_cleanup_flow_entirely
      end
    end

    assert(GitHubModels::Attachment.count.zero?)
  end

  test "attachments younger than a week arent deleted" do
    travel_to 20.days.ago do
      save_file_for_uploadable(GitHubModels::Attachment.new(uploader: @user))
      save_file_for_uploadable(GitHubModels::Attachment.new(uploader: @user))
    end

    newer_file = save_file_for_uploadable(GitHubModels::Attachment.new(uploader: @user))

    assert_equal(3, GitHubModels::Attachment.count)

    assert_difference("GitHubModels::Attachment.count", -2) do
      perform_cleanup_flow_entirely
    end

    assert(GitHubModels::Attachment.exists?(newer_file.id))
  end

end if GitHub.models_enabled?
