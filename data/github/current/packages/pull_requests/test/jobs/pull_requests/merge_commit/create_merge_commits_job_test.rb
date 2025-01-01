# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    class CreateMergeCommitsJobTest < GitHub::TestCase
      include GitHub::LoggerHelper

      fixtures do
        @user = create :user, login: "whimsycat"

        @repo = create :private_repository, owner: @user, name: "Whimsy", from_example: :pull_request_fork

        @pull = PullRequest.create_for @repo,
          user: @user,
          base: "master",
          head: "topic",
          title: "Whimsee",
          body: "Moar whimsea"

        make_trusted_oauth_apps_owner
        @merge_commit_update_refs_app = create(:merge_commit_update_refs_integration)
      end

      test "it allows processing with the new engine" do
        disable_feature_flag(:disable_merge_commit_create_commits_jobs)

        CreateMergeCommitsJob.perform_now(@pull)

        refute_empty MergeCommitRequest.where(repository_id: @repo.id, pull_request_id: @pull.id)
      end

      test "it allows disabling of the job per repo" do
        enable_feature_flag(:disable_merge_commit_create_commits_jobs, @repo)

        CreateMergeCommitsJob.perform_now(@pull)

        assert_empty MergeCommitRequest.where(repository_id: @repo.id, pull_request_id: @pull.id)
      end

      test "it gracefully retries and errors with repository repairing state" do
        Repository.any_instance.stubs(:repairing?).returns(true)

        assert_performed_jobs(19, only: CreateMergeCommitsJob) do
          CreateMergeCommitsJob.perform_now(@pull)
        end
      end

      context "job locking" do
        test "locks job per repository id" do
          second_pull = PullRequest.create_for @repo,
            user: @user,
            base: "master",
            head: "topic2",
            title: "Whimsee2",
            body: "Moar whimsea2"
          aquired = CreateMergeCommitsJob.new(@pull)

          Timecop.freeze(3.minutes.ago) do
            assert aquired.acquire_lock
            assert aquired.locked?
          end

          Timecop.freeze(Time.now) do
            assert_equal CreateMergeCommitsJob.new(@pull).acquire_lock, false
            assert CreateMergeCommitsJob.new(second_pull).acquire_lock
          end
        end

        test "new job can aquire a lock if the previous lock has expired" do
          expired = CreateMergeCommitsJob.new(@pull)

          Timecop.freeze(6.minutes.ago) do
            assert expired.acquire_lock
            assert expired.locked?
          end

          Timecop.freeze(Time.now) do
            assert_equal expired.locked?, false
            assert CreateMergeCommitsJob.new(@pull).acquire_lock
          end
        end
      end
    end
  end
end
