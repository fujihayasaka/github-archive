# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    class CommandTest < GitHub::TestCase
      include PullRequestSynchronizationTestHelpers
      include GitHub::LoggerHelper

      Spokesd.share_spokesdb(self)

      fixtures do
        @owner = create(:user, login: "ari")
        @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
        @forker = create(:user, login: "bwalsh")
        @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_fork)

        @issue = create(:issue, user: @forker, repository: @repo)
        @pull = PullRequest.create_for(@repo,
          base: "master",
          head: "#{@fork.user}:topic",
          user: @issue.user,
          issue: @issue)

        # NOTE: Due to the configuration of the MergeCommitRequest database schema, it does not work in these fixture blocks.
        # You'll get a confusing fixture error about `first.`

        example_repo_snapshot

        make_trusted_oauth_apps_owner
        @merge_commit_update_refs_app = create(:merge_commit_update_refs_integration)
      end

      setup do
        Spokesd.enable_spokesd

        GitHub.flipper[:notify_on_merge_state_change].enable

        example_repo_restore
      end

      context "insert_merge_commit_request!" do
        test "successfully inserts a merge commit request" do
          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          base_branch_sha = @pull.mergeable_base_sha
          head_branch_sha = @pull.mergeable_head_sha

          # test attributes only, values can be nonsense
          merge_commit_request_attrs = {
            pull_request_id: @pull.id,
            priority: Enums::Priority::High,
            base_repository_id: @pull.base_repository_id,
            head_repository_id: @pull.head_repository_id,
            base_branch_sha:,
            head_branch_sha:,
            merge_sha: @pull.base_sha,
            merge_state: Enums::CommitState::Created,
            merge_conflict: { "data" => "data2" },
            rebase_sha: @pull.head_sha,
            rebase_state: Enums::CommitState::Created,
            rebase_conflict: { "data3" => "data4" },
          }

          result = command.insert_merge_commit_request!(**merge_commit_request_attrs)
          fail unless result.is_a?(ICommand::Result::Success)

          merge_commit_request = MergeCommitRequest.find_by(pull_request_id: @pull.id, repository: @repo.id)
          fail "MergeCommitRequest record matching pull request and repo id was not found" unless merge_commit_request

          assert_subset_hash({
            priority: Enums::Priority::High.serialize,
            base_repository_id: @pull.base_repository_id,
            head_repository_id: @pull.head_repository_id,
            base_branch_sha:,
            head_branch_sha:,
            merge_sha: @pull.base_sha,
            merge_state: Enums::CommitState::Created.serialize,
            merge_conflict: { "data" => "data2" },
            rebase_sha: @pull.head_sha,
            rebase_state: Enums::CommitState::Created.serialize,
            rebase_conflict: { "data3" => "data4" },
          }.stringify_keys, merge_commit_request.attributes)
        end

        test "it successfully updates a merge commit request if one with the same pull request id and repository id already exists" do
          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          assert_equal 0, MergeCommitRequest.count

          base_branch_sha = @pull.mergeable_base_sha
          head_branch_sha = @pull.mergeable_head_sha

          # test attributes only, values can be nonsense
          merge_commit_request_attrs = {
            pull_request_id: @pull.id,
            priority: Enums::Priority::High,
            base_repository_id: @pull.base_repository_id,
            head_repository_id: @pull.head_repository_id,
            base_branch_sha:,
            head_branch_sha:,
            merge_sha: @pull.base_sha,
            merge_state: Enums::CommitState::Created,
            merge_conflict: { "data" => "data2" },
            rebase_sha: @pull.head_sha,
            rebase_state: Enums::CommitState::Created,
            rebase_conflict: { "data3" => "data4" },
          }

          # alert the values and add ones that are needed with a direct create!
          mcr_database_creation_attrs = merge_commit_request_attrs.merge({
            repository_id: @repo.id,
            priority: Enums::Priority::Low.serialize,
            merge_state: Enums::CommitState::Failed.serialize,
            rebase_state: Enums::CommitState::Failed.serialize,
            base_repository_id: 42,
            head_repository_id: 84,
          })

          MergeCommitRequest.create!(mcr_database_creation_attrs)

          result = command.insert_merge_commit_request!(**merge_commit_request_attrs)
          fail "Insert merge commit request was not successful with error: #{result.inspect}" unless result.is_a?(ICommand::Result::Success)

          assert_equal 1, MergeCommitRequest.count

          merge_commit_request = MergeCommitRequest.find_by(pull_request_id: @pull.id, repository: @repo.id)
          fail "MergeCommitRequest record matching pull request and repo id was not found" unless merge_commit_request

          assert_subset_hash({
            priority: Enums::Priority::High.serialize,
            base_repository_id: @pull.base_repository_id,
            head_repository_id: @pull.head_repository_id,
            base_branch_sha:,
            head_branch_sha:,
            merge_sha: @pull.base_sha,
            merge_state: Enums::CommitState::Created.serialize,
            merge_conflict: { "data" => "data2" },
            rebase_sha: @pull.head_sha,
            rebase_state: Enums::CommitState::Created.serialize,
            rebase_conflict: { "data3" => "data4" },
          }.stringify_keys, merge_commit_request.attributes)
        end

        test "returns an error if there was an error when inserting a merge commit request" do
          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          base_branch_sha = @pull.mergeable_base_sha
          head_branch_sha = @pull.mergeable_head_sha

          # test attributes only, values can be nonsense
          merge_commit_request_attrs = {
            pull_request_id: @pull.id,
            priority: Enums::Priority::High,
            base_repository_id: @pull.base_repository_id,
            head_repository_id: @pull.head_repository_id,
            base_branch_sha:,
            head_branch_sha:,
            merge_sha: @pull.base_sha,
            merge_state: Enums::CommitState::Created,
            merge_conflict: { "data" => "data2" },
            rebase_sha: @pull.head_sha,
            rebase_state: Enums::CommitState::Created,
            rebase_conflict: { "data3" => "data4" },
          }

          MergeCommitRequest.expects(:upsert).once.raises(ActiveRecord::QueryCanceled.new("timeout error"))
          result = command.insert_merge_commit_request!(**merge_commit_request_attrs)
          fail unless result.is_a?(ICommand::Result::Error)

          assert_equal "timeout error", result.message

          merge_commit_request = MergeCommitRequest.find_by(pull_request_id: @pull.id, repository: @repo.id)
          fail "MergeCommitRequest record matching pull request and repo id was found" if merge_commit_request
        end
      end

      context "transition_to_processing!" do
        test "it updates the database records for the requests to processing" do
          skip("Updating merge_commit_requests_table: https://github.com/github/pull-requests/issues/13217")

          pull_request_id = @pull.id

          request = MergeCommitRequest.create(
            pull_request_id:,
            repository_id: @repo.id
          )

          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          refute request.processing?

          command.transition_to_processing!(pull_request_ids: [pull_request_id])

          assert request.reload.processing?
        end
      end

      context "enqueue_batch_ref_updates_job!" do
        test "successfully enqueues a job" do
          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          assert_enqueued_jobs 1, only: PullRequests::MergeCommit::BatchRefUpdatesJob do
            result = command.enqueue_batch_ref_updates_job!(pull_request_id: @pull.id)
            fail "enqueue failed" unless result.is_a?(ICommand::Result::Success)
          end

          result = command.enqueue_batch_ref_updates_job!(pull_request_id: @pull.id)
          fail "enqueue failed due to locking error" unless result.is_a?(ICommand::Result::Success)
        end
      end

      context "create_merge_commit!" do
        test "successfully creates a merge commit" do
          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          base_sha, head_sha = base_and_head_sha_for(@pull)

          result = command.create_merge_commit!(
            pull_request_id: @pull.id,
            base_sha:,
            head_sha:,
          )

          fail unless result.is_a?(PullRequests::GitSystems::Commit::Created)

          assert result.sha
        end

        test "reports a merge conflict" do
          ensure_pull_has_merge_conflict

          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          base_sha, head_sha = base_and_head_sha_for(@pull)

          result = command.create_merge_commit!(
            pull_request_id: @pull.id,
            base_sha:,
            head_sha:,
          )

          fail unless result.is_a?(PullRequests::GitSystems::Commit::Conflict)

          assert result.details.present?
        end

        test "stores a merge conflict" do
          ensure_pull_has_merge_conflict

          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          base_sha, head_sha = base_and_head_sha_for(@pull)

          result = command.create_merge_commit!(
            pull_request_id: @pull.id,
            base_sha:,
            head_sha:,
          )

          fail unless result.is_a?(PullRequests::GitSystems::Commit::Conflict)

          assert @pull.reload.conflict.present?
        end

        test "returns an error code" do
          stub_create_merge_commit_to_error

          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          base_sha, head_sha = base_and_head_sha_for(@pull)

          result = command.create_merge_commit!(
            pull_request_id: @pull.id,
            base_sha:,
            head_sha:,
          )

          fail unless result.is_a?(PullRequests::GitSystems::Commit::Failed)

          assert_equal result.code, :error
        end
      end

      context "delete_processing_requests" do
        test "successfully deletes processing requests" do
          skip("Updating merge_commit_requests_table: https://github.com/github/pull-requests/issues/13217")

          pull_request_id = @pull.id
          repository_id = @repo.id

          request = MergeCommitRequest.create(
            pull_request_id:,
            repository_id:,
            processing: true
          )

          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          result = command.delete_processing_requests!(pull_request_ids: [pull_request_id])

          fail unless result.is_a?(ICommand::Result::Success)

          assert_equal 0, MergeCommitRequest.where(pull_request_id:, repository_id:).count
        end

        test "does not delete requests where processing is false" do
          skip("Updating merge_commit_requests_table, https://github.com/github/pull-requests/issues/13217")

          pull_request_id = @pull.id
          repository_id = @repo.id

          request = MergeCommitRequest.create(
            pull_request_id:,
            repository_id:,
            processing: false
          )

          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          result = command.delete_processing_requests!(
            pull_request_ids: [pull_request_id]
          )

          fail unless result.is_a?(ICommand::Result::Success)

          assert_equal 1, MergeCommitRequest.where(pull_request_id:, repository_id:).count
        end
      end

      context "create_rebase_commit!" do
        test "successfully creates a rebase commit" do
          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          pull_request_id = @pull.id
          base_sha, head_sha = base_and_head_sha_for(@pull)

          merge_commit_result = command.create_merge_commit!(
            pull_request_id:,
            base_sha:,
            head_sha:,
          )

          merge_commit_sha = case merge_commit_result
          when PullRequests::GitSystems::Commit::Created
            merge_commit_result.sha
          else
            fail "this should be unreachable unless rpc under test is broken"
          end

          timeout = 7

          result = command.create_rebase_commit!(
            pull_request_id:,
            base_sha:,
            merge_commit_sha:,
            timeout:
          )

          fail unless result.is_a?(PullRequests::GitSystems::Commit::Created)

          assert result.sha
        end

        test "clears prior rebase conflicts" do
          @pull.store_rebase_conflicts

          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          pull_request_id = @pull.id
          base_sha, head_sha = base_and_head_sha_for(@pull)

          merge_commit_result = command.create_merge_commit!(
            pull_request_id:,
            base_sha:,
            head_sha:,
          )

          merge_commit_sha = case merge_commit_result
          when PullRequests::GitSystems::Commit::Created
            merge_commit_result.sha
          else
            fail "this should be unreachable unless rpc under test is broken"
          end

          assert @pull.rebase_conflicts?

          result = command.create_rebase_commit!(
            pull_request_id:,
            base_sha:,
            merge_commit_sha:,
            timeout: 7
          )

          fail unless result.is_a?(PullRequests::GitSystems::Commit::Created)

          assert_nil @pull.reload.rebase_conflict
        end

        test "stores new rebase conflicts" do
          ensure_pull_has_rebase_conflict

          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          pull_request_id = @pull.id
          base_sha, head_sha = base_and_head_sha_for(@pull)

          merge_commit_result = command.create_merge_commit!(
            pull_request_id:,
            base_sha:,
            head_sha:,
          )

          merge_commit_sha = case merge_commit_result
          when PullRequests::GitSystems::Commit::Created
            merge_commit_result.sha
          else
            fail "this should be unreachable unless rpc under test is broken"
          end

          timeout = 7

          refute @pull.rebase_conflicts?

          result = command.create_rebase_commit!(
            pull_request_id:,
            base_sha:,
            merge_commit_sha:,
            timeout:
          )

          fail unless result.is_a?(PullRequests::GitSystems::Commit::Conflict)

          assert @pull.reload.rebase_conflicts?
        end
      end

      context "update_refs!" do
        test "calls batch_write_refs with what we expect for one pr" do
          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          pull_request_id = @pull.id
          base_sha, head_sha = base_and_head_sha_for(@pull)
          merge_ref_name = @pull.merge_ref
          rebase_ref_name = @pull.rebase_ref

          merge_commit = GitSystems::Commit::Created.new(
            sha: "placeholder",
            base_sha:,
            head_sha:
          )

          rebase_commit = GitSystems::Commit::Created.new(
            sha: "replaceholder",
            base_sha:,
            head_sha: merge_commit.oid,
          )

          @repo.expects(:batch_write_refs).with(
            GitHub.merge_commit_update_refs_bot,
            [[merge_ref_name, nil, merge_commit.sha], [rebase_ref_name, nil, rebase_commit.sha]],
            priority: :low,
            no_custom_hooks: true,
          )

          merge_update = ICommand::RefUpdate.new(
            pull_request_id:,
            name: merge_ref_name,
            sha: merge_commit.sha,
          )

          rebase_update = ICommand::RefUpdate.new(
            pull_request_id:,
            name: rebase_ref_name,
            sha: rebase_commit.sha,
          )

          result = command.update_refs!(updates: [merge_update, rebase_update])
          fail unless result.is_a?(ICommand::Result::Success)
        end

        test "returns an error if the ref update has an exception" do
          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          @repo.expects(:batch_write_refs).raises(Git::Ref::UpdateFailedSensitive.new("git-update-ref failed"))

          merge_update = ICommand::RefUpdate.new(
            pull_request_id: @pull.id,
            name: @pull.merge_ref,
            sha: "placeholder",
          )

          result = command.update_refs!(updates: [merge_update])
          fail unless result.is_a?(ICommand::Result::Error)
        end
      end

      context "transition_invalid_request_to_mergeable!" do
        test "updates a mergeable pull request" do
          command = Command.new(pull_requests: [@pull], repository: @repo)

          @pull.expects(:synchronize_search_index).at_least_once
          @pull.expects(:notify_git_merge_state_channel).at_least_once

          result = command.transition_invalid_request_to_mergeable!(
            pull_request_id: @pull.id
          )

          fail unless result.is_a?(ICommand::Result::Success)

          assert @pull.mergeable
        end
      end

      context "mark_pull_request_as_mergeable!" do
        test "updates a mergeable pull request" do
          command = Command.new(pull_requests: [@pull], repository: @repo)

          merge_commit_sha = "placeholder"

          @pull.expects(:synchronize_search_index).at_least_once
          @pull.expects(:notify_git_merge_state_channel).at_least_once

          result = command.mark_pull_request_as_mergeable!(
            pull_request_id: @pull.id,
            merge_commit_sha:
          )

          fail unless result.is_a?(ICommand::Result::Success)

          assert @pull.mergeable
          assert_equal merge_commit_sha, @pull.merge_commit_sha
        end

        test "updates a mergeable pull request that was previously conflicted" do
          @pull.update(mergeable: false)

          command = Command.new(pull_requests: [@pull], repository: @repo)
          merge_commit_sha = "placeholder"

          @pull.expects(:synchronize_search_index).at_least_once
          @pull.expects(:notify_git_merge_state_channel).at_least_once

          result = command.mark_pull_request_as_mergeable!(
            pull_request_id: @pull.id,
            merge_commit_sha:
          )

          fail unless result.is_a?(ICommand::Result::Success)

          assert @pull.mergeable
          assert_equal merge_commit_sha, @pull.merge_commit_sha
          refute @pull.reload.conflict
        end
      end

      context "dispatch_mergeability_event!" do
        test "emits instrumentation" do
          @pull.update(mergeable: false)
          create_conflict_data_for(@pull)
          events = subscribe("pull_request.mergeability")

          command = Command.new(pull_requests: [@pull], repository: @repo)

          command.dispatch_mergeability_event!(
            pull_request_id: @pull.id
          )

          assert event = events.pop
          assert_subset_hash({ pull_request_id: @pull.id, mergeable: false }, event.payload)
        end
      end

      context "mark_pull_request_as_unmergeable!" do
        test "updates a non-mergeable pull request" do
          create_conflict_data_for(@pull)

          events = subscribe("pull_request.mergeability")
          command = Command.new(pull_requests: [@pull], repository: @repo)

          GitHub::WebSocket::Channels.expects(:pull_request_git_merge_state).once

          result = command.mark_pull_request_as_unmergeable!(
            pull_request_id: @pull.id
          )

          fail unless result.is_a?(ICommand::Result::Success)

          refute @pull.mergeable
        end
      end

      context "clear_mergeability!" do
        test "clears the mergeability status if something goes wrong" do
          @pull.update(mergeable: true, merge_commit_sha: "placeholder")

          command = Command.new(
            pull_requests: [@pull],
            repository: @repo
          )

          result = command.clear_mergeability!(
            pull_request_id: @pull.id
          )

          fail unless result.is_a?(ICommand::Result::Success)

          assert_nil @pull.mergeable
          assert_nil @pull.merge_commit_sha
        end
      end

      private

      def ensure_pull_has_merge_conflict
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
      end

      def ensure_pull_has_rebase_conflict
        with_enqueued_pr_sync_jobs(additional_jobs: [MaintainTrackingRefJob]) do
          @repo.refs.find("master").append_commit({
            message: "Commit on master",
            committer: @owner,
          }, @owner) do |files|
            files.add("README.md", "Will this conflict?")
          end

          topic_ref = @fork.refs.find("topic")

          topic_ref.append_commit({
            message: "Commit on topic",
            committer: @forker,
          }, @forker) do |files|
            files.add("README.md", "This will conflict")
          end

          topic_ref.append_commit({
            message: "Commit on topic",
            committer: @forker,
          }, @forker) do |files|
            files.remove("README.md")
          end

          topic_ref.append_commit({
            message: "Commit on topic",
            committer: @forker,
          }, @forker) do |files|
            files.add("README.md", "Will this conflict?")
          end
        end

        @pull.reload
      end

      def stub_create_merge_commit_to_error
        Repository.any_instance.stubs(:disable_libgit2_to_git_experiments).returns(true)
        if @repo.feature_enabled?(:tmp_objdir_experiment)
          @repo.rpc.expects(:create_merge_commit).once.returns(
            ["BOOM", "error", nil, nil, [["rebase.dogstats.mock", 1, { tags: ["status:failure"] }]]]
          )
        else
          @repo.rpc.expects(:create_merge_commit).once.returns(%w[BOOM error])
        end
      end

      sig { params(pull: PullRequest).returns([String, String]) }
      def base_and_head_sha_for(pull)
        [pull.mergeable_base_sha.to_s, pull.mergeable_head_sha.to_s]
      end

      sig { params(pull: PullRequest).void }
      def create_conflict_data_for(pull = @pull)
        base, head = base_and_head_sha_for(pull)
        pull.store_conflicts({
          base:,
          head:,
          conflicted_files: { "example.txt" => true }
        }, conflict_type: :merge_conflict)
      end
    end
  end
end
