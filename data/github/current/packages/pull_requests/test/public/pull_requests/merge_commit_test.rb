# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestsMergeCommitTest < GitHub::TestCase
  include HydroTestHelpers
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
    context "when the repository has the `use_merge_commit_request_architecture` feature disabled" do
      test "creates a new CreatePullRequestMergeCommitJob" do
        GitHub.flipper[:use_merge_commit_request_architecture].disable
        Rails.env.stubs(:test?).returns(false)
        @pull.stubs(:currently_mergeable?).returns(nil)

        CreatePullRequestMergeCommitJob.expects(:perform_later).with(@pull.id)
        PullRequests::MergeCommit.enqueue_create(pull_request: @pull)

        refute_hydro_messages(schema: "github.pull_requests.v1.MergeCommitRequested")
      end
    end

    context "when the repository has the `use_merge_commit_request_architecture` feature enabled" do
      test "emits a hydro event" do
        GitHub.flipper[:use_merge_commit_request_architecture].enable
        Rails.env.stubs(:test?).returns(false)
        @pull.stubs(:currently_mergeable?).returns(nil)

        CreatePullRequestMergeCommitJob.expects(:perform_later).never
        PullRequests::MergeCommit.enqueue_create(pull_request: @pull)

        assert_hydro_published({
          repository_id: @repo.id,
          pull_request_id: @pull.id,
        }, schema: "github.pull_requests.v1.MergeCommitRequested")
      end
    end

    context "when the new_engine_override argument passed is 'true'" do
      test "emits a hydro event" do
        GitHub.flipper[:use_merge_commit_request_architecture].disable
        Rails.env.stubs(:test?).returns(false)
        @pull.stubs(:currently_mergeable?).returns(nil)

        CreatePullRequestMergeCommitJob.expects(:perform_later).never
        PullRequests::MergeCommit.enqueue_create(pull_request: @pull, new_engine_override: true)

        assert_hydro_published({
          repository_id: @repo.id,
          pull_request_id: @pull.id,
        }, schema: "github.pull_requests.v1.MergeCommitRequested")
      end
    end

    context "when the 'priority' argument passed is 'high'" do
      context "when the `skip_processor_batchable_mcr_jobs` and `use_merge_commit_request_architecture` feature flags are enabled" do
        test "emits a hydro event" do
          GitHub.flipper[:use_merge_commit_request_architecture].enable
          GitHub.flipper[:skip_processor_batchable_mcr_jobs].enable
          Rails.env.stubs(:test?).returns(false)
          @pull.stubs(:currently_mergeable?).returns(nil)

          CreatePullRequestMergeCommitJob.expects(:perform_later).never
          PullRequests::MergeCommitRequestBatchJob.expects(:perform_later).with(@repo.id)
          PullRequests::MergeCommit.enqueue_create(pull_request: @pull, priority: :high)

          refute_hydro_messages(schema: "github.pull_requests.v1.MergeCommitRequested")
        end
      end

      context "when the `skip_processor_batchable_mcr_jobs` feature flag is disable and the `use_merge_commit_request_architecture` feature flag is enabled" do
        test "emits a hydro event" do
          GitHub.flipper[:use_merge_commit_request_architecture].enable
          GitHub.flipper[:skip_processor_batchable_mcr_jobs].disable
          Rails.env.stubs(:test?).returns(false)
          @pull.stubs(:currently_mergeable?).returns(nil)

          CreatePullRequestMergeCommitJob.expects(:perform_later).never
          PullRequests::MergeCommit.enqueue_create(pull_request: @pull, priority: :high)

          assert_hydro_published({
            repository_id: @repo.id,
            pull_request_id: @pull.id,
          }, schema: "github.pull_requests.v1.MergeCommitRequested")
        end
      end
    end

    context "when a repository has been specifically blocked" do
      test "creates a new CreatePullRequestMergeCommitJob" do
        GitHub.flipper[:use_merge_commit_request_architecture].enable
        @repo.stubs(:id).returns(15539164)

        CreatePullRequestMergeCommitJob.expects(:perform_later).with(@pull.id)
        PullRequests::MergeCommit.enqueue_create(pull_request: @pull)

        refute_hydro_messages(schema: "github.pull_requests.v1.MergeCommitRequested")
      end
    end
  end

  context "#request!" do
    context "#create_merge_commit_request" do
      test "creates a new MergeCommitRequest record" do
        assert_equal MergeCommitRequest.count, 0

        PullRequests::MergeCommit.request!(repository_id: @repo.id, pull_request_id: @pull.id)

        assert_dogstats_count 1, "pull_requests.merge_commit_requests.created", tags: ["source:single"]
        assert_equal MergeCommitRequest.count, 1
      end

      test "records error metrics if a conflicting MergeCommitRequest record already exists" do
        MergeCommitRequest.create!(repository_id: @repo.id, pull_request_id: @pull.id)

        assert_equal MergeCommitRequest.count, 1

        PullRequests::MergeCommit.request!(repository_id: @repo.id, pull_request_id: @pull.id)

        assert_dogstats_increment 1, "pull_requests.merge_commit_requests.error", tags: ["error:record_not_unique"]
        assert_equal MergeCommitRequest.count, 1
      end

      test "records error metrics and reports to Sentry if an unexpected error occurs" do
        exception = ::Redis::TimeoutError.new("whimsical error")
        MergeCommitRequest.expects(:create!).with(repository_id: @repo.id, pull_request_id: @pull.id).raises(exception)

        expected_log = {
          Body: "merge commit request record could not be created",
          "error.type": "timeout_error",
          "error.message": "whimsical error",
          "gh.repo.id": @repo.id,
          "gh.pull.id": @pull.id
        }

        Failbot.expects(:report).with(exception)

        assert_logged(**expected_log) do
          PullRequests::MergeCommit.request!(repository_id: @repo.id, pull_request_id: @pull.id)
        end

        assert_dogstats_increment 1, "pull_requests.merge_commit_requests.error", tags: ["error:timeout_error"]
        assert_equal MergeCommitRequest.count, 0
      end
    end

    context "#enqueue_merge_commit_request_batch_job" do
      test "creates a new PullRequests::MergeCommitRequestBatchJob" do
        PullRequests::MergeCommitRequestBatchJob.expects(:perform_later).with(@repo.id)
        PullRequests::MergeCommit.request!(repository_id: @repo.id, pull_request_id: @pull.id)
      end
    end
  end
end
