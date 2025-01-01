# typed: true
# frozen_string_literal: true
require "test_helper"

module PullRequests
  class MergeCommitRequestBatchJobTest < GitHub::TestCase
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

      @feature = create(:flipper_feature, name: "size_of_batchable_cprmc_jobs", description: "test feature flag")
      @feature.enable_percentage_of_time(1)
    end

    test "it allows processing with the new engine" do
      GitHub.flipper[:disable_merge_commit_request_batch_jobs].disable

      MergeCommitRequest.create!(repository_id: @repo.id, pull_request_id: @pull.id)

      PullRequests::MergeCommitRequestBatchJob.perform_now(@repo.id)

      assert_empty MergeCommitRequest.where(repository_id: @repo.id, pull_request_id: @pull.id)
    end

    test "it allows disabling of the job per repo" do
      GitHub.flipper[:disable_merge_commit_request_batch_jobs].enable(@repo)
      MergeCommitRequest.create!(repository_id: @repo.id, pull_request_id: @pull.id)

      PullRequests::MergeCommitRequestBatchJob.perform_now(@repo.id)

      refute_empty MergeCommitRequest.where(repository_id: @repo.id, pull_request_id: @pull.id)
    end

    context "job locking" do
      test "locks job per repository id" do
        second_repo = create :private_repository, owner: @user, name: "WhimsyToo", from_example: :pull_request_fork
        aquired = PullRequests::MergeCommitRequestBatchJob.new(@repo.id)

        Timecop.freeze(3.minutes.ago) do
          assert aquired.acquire_lock
          assert aquired.locked?
        end

        Timecop.freeze(Time.now) do
          assert_equal PullRequests::MergeCommitRequestBatchJob.new(@repo.id).acquire_lock, false
          assert PullRequests::MergeCommitRequestBatchJob.new(second_repo.id).acquire_lock
        end
      end

      test "new job can aquire a lock if the previous lock has expired" do
        expired = PullRequests::MergeCommitRequestBatchJob.new(@repo.id)

        Timecop.freeze(6.minutes.ago) do
          assert expired.acquire_lock
          assert expired.locked?
        end

        Timecop.freeze(Time.now) do
          assert_equal expired.locked?, false
          assert PullRequests::MergeCommitRequestBatchJob.new(@repo.id).acquire_lock
        end
      end
    end
  end
end
