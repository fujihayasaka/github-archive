# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DeleteRepositoryFilesByUserIdJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user, login: "leonardovillela")
    create_list(:repository_file, 3, uploader: @user)
    @last_repository_file = RepositoryFile.last

    @monalisa = create(:user, login: "monalisa")
    create(:repository_file, uploader: @monalisa)
  end

  test "retries on job dirty exit" do
    assert_retry_on_dirty_exit(job: DeleteRepositoryFilesByUserIdJob)
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions(job: DeleteRepositoryFilesByUserIdJob)
  end

  test "retries on database throttle" do
    assert_retry_on_throttler_error(job: DeleteRepositoryFilesByUserIdJob, args: [{ user_id: @user.id }], using_kwargs: true)
  end

  context "deletes by user_id" do
    test "deletes all associated repository files" do
      assert_difference(-> { RepositoryFile.count } => -3) do
        DeleteRepositoryFilesByUserIdJob.perform_now(user_id: @user.id)
      end

      refute RepositoryFile.exists?(@last_repository_file.id)
    end

    test "does not delete other repository files" do
      assert_no_difference(-> { RepositoryFile.where(uploader_id: @monalisa.id).count }) do
        DeleteRepositoryFilesByUserIdJob.perform_now(user_id: @user.id)
      end
    end
  end

  context "deletes by files_ids" do
    test "deletes all repository files by ids" do
      assert_difference(-> { RepositoryFile.count } => -1) do
        DeleteRepositoryFilesByUserIdJob.perform_now(user_id: @user.id, files_ids: [@last_repository_file.id])
      end

      refute RepositoryFile.exists?(@last_repository_file.id)
    end

    test "does not delete repository files with other ids" do
      assert_no_difference(-> { RepositoryFile.where(uploader_id: @monalisa.id).count }) do
        DeleteRepositoryFilesByUserIdJob.perform_now(user_id: @user.id, files_ids: [@last_repository_file.id])
      end
    end

    test "does not raise errors when asset does not exist or was already deleted" do
      RepositoryFile.delete_all

      assert_nothing_raised do
        DeleteRepositoryFilesByUserIdJob.perform_now(user_id: @user.id, files_ids: [@last_repository_file.id])
      end
    end
  end
end
