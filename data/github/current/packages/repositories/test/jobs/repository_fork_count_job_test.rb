# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RepositoryForkCountJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @repo = create(:repository, from_example: :simple)
    @user1 = create(:user)
    @fork1 = create(:fork_repository, forker: @user1, fork_repo: @repo)
    @user2 = create(:user)
    @fork2 = create(:fork_repository, forker: @user2, fork_repo: @repo)
    @user3 = create(:user)
    @fork3 = create(:fork_repository, forker: @user3, fork_repo: @repo)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
    enable_feature_flag(:repo_fork_count_job)
  end

  test "returns early when repo to be processed does not exist" do
    result = RepositoryForkCountJob.perform_now(Repository.last&.id + 12345)
    assert_nil result
  end

  test "runs fork count on the repository when user marked spammy" do
    skip unless GitHub.spamminess_check_enabled?

    assert_equal 3, @repo.public_fork_count

    perform_enqueued_jobs(only: [UpdateTableUserHiddenJob, UserForkCountJob]) do
      @user1.mark_as_spammy
      @user3.mark_as_spammy
    end

    perform_enqueued_jobs(only: [RepositoryForkCountJob])

    assert_equal 1, @repo.reload.public_fork_count
  end

  test "retry conditions" do
    assert_retry_on_dirty_exit job: RepositoryForkCountJob, args: [@repo.id]
  end
end
