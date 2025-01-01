# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestsMergeCommitTest < GitHub::TestCase
  include DogstatsTestHelpers
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
  end

  context "#enqueue_create" do
    context "when the `disable_mcr_engine` feature is enabled" do
      test "enqueues a new CreatePullRequestMergeCommitJob" do
        GitHub.flipper[:disable_mcr_engine].enable
        @pull.stubs(:currently_mergeable?).returns(nil)

        assert_enqueued_with(job: CreatePullRequestMergeCommitJob, args: [@pull.id]) do
          PullRequests::MergeCommit.enqueue_create(pull_request: @pull)
        end
      end
    end

    context "when the `disable_mcr_engine` feature is disabled" do
      test "enqueues a new PullRequests::MergeCommit::CreateMergeCommitsJob" do
        # this feature flag is disabled by default in test via the FeatureFlag::AllFeatures class, but we're purposefully
        # disabling it here for easier triage in the future should anything go wrong with it
        GitHub.flipper[:disable_mcr_engine].disable
        @pull.stubs(:currently_mergeable?).returns(nil)

        assert_enqueued_with(job: PullRequests::MergeCommit::CreateMergeCommitsJob, args: [@pull, priority: PullRequests::MergeCommit::Enums::Priority::Low.serialize]) do
          PullRequests::MergeCommit.enqueue_create(pull_request: @pull)
        end
      end
    end

    test "reverts to using CreatePullRequestMergeCommitJob when merge commit requests have been paused" do
      GitHub.flipper[:use_two_job_mcr_engine].enable
      GitHub.flipper[:mcr_blocked_repo_override].disable
      MergeCommitRequest.set_paused_for(@repo)

      PullRequests::MergeCommit::BatchRefUpdatesJob.expects(:perform_later).never
      PullRequests::MergeCommit::CreateMergeCommitsJob.expects(:perform_later).never

      assert_enqueued_with(job: CreatePullRequestMergeCommitJob, args: [@pull.id]) do
        PullRequests::MergeCommit.enqueue_create(pull_request: @pull)
      end
    end
  end
end
