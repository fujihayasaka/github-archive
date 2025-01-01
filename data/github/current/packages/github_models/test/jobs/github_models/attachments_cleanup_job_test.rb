# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubModels::AttachmentsCleanupJobTest < GitHub::TestCase
  include UploadableTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @user = create(:user)
  end

  sig { params(attachment: GitHubModels::Attachment).returns(String) }
  def attachment_path(attachment)
    "/#{GitHub.models_attachment_azure_storage_bucket}/#{attachment.storage_s3_key(attachment.storage_policy)}"
  end

  test "simply deletes" do
    attachment = T.let(save_file_for_uploadable(GitHubModels::Attachment.new(uploader: @user)), GitHubModels::Attachment)

    assert_logged(
      Body: "Destroyed github models attachment",
      "gh.job.name": "GitHubModels::AttachmentsCleanupJob",
      "gh.job.arguments": "[#{attachment.id}]",
      "gh.github_models.attachment.id": attachment.id,
    ) do
      assert_difference("GitHubModels::Attachment.count", -1) do
        GitHubModels::AttachmentsCleanupJob.perform_now(attachment.id)
      end

      refute(GitHubModels::Attachment.exists?(attachment.id))
    end
  end

  test "locks job with same attachment id" do
    attachment = T.let(save_file_for_uploadable(GitHubModels::Attachment.new(uploader: @user)), GitHubModels::Attachment)

    assert_enqueued_jobs(1, only: GitHubModels::AttachmentsCleanupJob) do
      job = GitHubModels::AttachmentsCleanupJob.perform_later(attachment.id)

      assert_predicate(job, :locked?)
      assert_equal(attachment.id.to_s, T.unsafe(job).lock_key)

      GitHubModels::AttachmentsCleanupJob.perform_later(attachment.id)
    end
  end

  test "fails when attachment fails to delete" do
    attachment = T.let(save_file_for_uploadable(GitHubModels::Attachment.new(uploader: @user)), GitHubModels::Attachment)

    perform_enqueued_jobs(only: GitHubModels::AttachmentsCleanupJob) do
      assert_storage_policy_delete(attachment, attachment_path(attachment), delete_status: 500) do
        assert_raises(Storage::Uploadable::DeletionError) do
          assert_logged("gh.job.exectuions": 3) do
            GitHubModels::AttachmentsCleanupJob.perform_now(attachment.id)
          end
        end
      end
    end
  end

end if GitHub.models_enabled?
