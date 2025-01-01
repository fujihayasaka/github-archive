# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    module Integration
      class RepositoryTest < GitHub::TestCase
        include PullRequestSynchronizationTestHelpers

        Spokesd.share_spokesdb(self)

        fixtures do
          @owner = create(:user, login: "ari")
          @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
          @forker = create(:user, login: "bwalsh")
          @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_fork)

          @pull = PullRequest.create_for(@repo,
            base: "master",
            head: "#{@fork.user}:topic",
            user: @forker,
            issue: create(:issue, user: @forker, repository: @repo))

          @pull_2 = PullRequest.create_for(@repo,
            base: "master",
            head: "#{@fork.user}:master-plus-one-commit",
            user: @forker,
            issue: create(:issue, user: @forker, repository: @repo)).tap(&:save!)

          # NOTE: Due to the configuration of the MergeCommitRequest database schema, it does not work in these fixture blocks.
          # You'll get a confusing fixture error about `first.`

          @feature = create(:flipper_feature, name: "size_of_batchable_cprmc_jobs", description: "test feature flag")
          @feature.enable_percentage_of_time(1)

          example_repo_snapshot

          make_trusted_oauth_apps_owner
          @merge_commit_update_refs_app = create(:merge_commit_update_refs_integration)

          @repo.disable_feature(:disable_merge_commit_request_batch_jobs)

          GitHub.flipper[:disable_merge_commit_create_commits_jobs].disable
        end

        setup do
          Spokesd.enable_spokesd
          example_repo_restore
        end

        test "creating a merge and rebase commit for a PR" do
          # Should not be initially mergeable.
          refute @pull.mergeable
          refute @pull.merge_commit_sha

          # Run the CPRMC process.
          perform_enqueued_jobs only: [CreateMergeCommitsJob, BatchRefUpdatesJob] do
            # TODO: Swap this to the public interface.
            CreateMergeCommitsJob.perform_later(@pull)
          end

          # All requests should be cleaned up.
          assert_equal 0, MergeCommitRequest.where(repository_id: @repo.id).count

          # PR should be mergeable.
          assert PullRequest.find(@pull.id).currently_mergeable?

          @pull.reload

          # Merge ref should have been created and the database commit SHA should match.
          merge_ref = @pull.repository.refs.read(@pull.merge_ref)
          assert merge_ref.exists?
          assert_equal merge_ref.sha, @pull.merge_commit_sha

          # Rebase ref should have been created with an internal namespace.
          assert @pull.repository.internal_refs.read(@pull.rebase_ref).exists?
        end

        test "creating a conflicting merge commit for a PR" do
          # Generate a real git conflict.
          with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
            @repo.refs.find("master").append_commit({
              message: "Commit on master",
              committer: @owner,
            }, @owner) do |files|
              files.add("README.md", "Will this conflict?")
            end

            @fork.refs.find("topic").append_commit({
              message: "Commit on topic",
              committer: @forker,
            }, @forker) do |files|
              files.add("README.md", "This will conflict")
            end
          end

          @pull.reload

          # PR should not be initially mergeable.
          refute @pull.mergeable
          refute @pull.merge_commit_sha

          # Run the CPRMC process.
          perform_enqueued_jobs only: [CreateMergeCommitsJob, BatchRefUpdatesJob] do
            # TODO: Swap this to the public interface.
            CreateMergeCommitsJob.perform_later(@pull)
          end

          # All requests should be cleaned up.
          assert_equal 0, MergeCommitRequest.where(repository_id: @repo.id).count

          pull = PullRequest.find(@pull.id)

          # PR should be marked as conflicted.
          assert_equal false, pull.currently_mergeable?

          # PR should have a stored DB conflict record.
          assert pull.conflict
        end
      end
    end
  end
end
