# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UserForkCountJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @repo1 = create(:repository, from_example: :simple)
    @repo2 = create(:repository, from_example: :simple)
    @user1 = create(:user)
    create(:fork_repository, forker: @user1, fork_repo: @repo1)
    create(:fork_repository, forker: @user1, fork_repo: @repo2)
    @user2 = create(:user)
    create(:fork_repository, forker: @user2, fork_repo: @repo1)
    create(:fork_repository, forker: @user2, fork_repo: @repo2)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
    enable_feature_flag(:repo_fork_count_job)
  end

  test "queues repository_fork_count_job once per parent repo" do
    assert_enqueued_jobs 2, only: RepositoryForkCountJob do
      UserForkCountJob.perform_now(@user1.id)
    end

    assert_enqueued_jobs 0, only: RepositoryForkCountJob do
      UserForkCountJob.perform_now(@user2.id)
    end
  end

  test "returns early when user does not exist" do
    result = UserForkCountJob.perform_now(User.last&.id + 12345)
    assert_nil result
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: UserForkCountJob, args: [@user1.id]
  end
end
