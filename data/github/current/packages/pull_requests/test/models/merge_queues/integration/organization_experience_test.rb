# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "integration_test_case"

module MergeQueues
  class OrganizationExperienceTest < IntegrationTestCase
    include DogstatsTestHelpers

    fixtures do
      Spokesd.enable_spokesd

      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      @org = create(:organization, plan: "business_plus")
      @repo = create(:public_repository, :has_merge_queue, owner: @org)
      @user = create(:user)
      @repo.add_member @user, action: :write
      @org.add_member @user, action: :write

      @queue = @repo.default_merge_queue

      disable_feature_flag(:merge_queue_uses_queue_refs, @repo)

      create :hook, :web, installation_target: @repo, events: %w(merge_group pull_request)

      example_repo_snapshot
    end

    test "a PR is enqueued, the checks pass, and the PR is merged" do
      pull, entry = enqueue_pull_request!(ref_name: "cr-line-endings")

      invoke_merge_queue_job!

      assert_entry_hook_delivered(entry, "checks_requested")

      simulate_check(entry, :success)

      # It should not queue a job in the future because everything settled.
      MergeQueues.expects(:delayed_execute!).never

      invoke_merge_queue_job!

      assert_queue_size 0

      assert pull.merged?
      assert_pull_request_hook_delivered(pull, "dequeued")

      assert entry.destroyed?
      assert_entry_hook_delivered(entry, "destroyed")
      assert_prep_branch_merged_for(pull)
      assert_prep_branch_created_for(pull)
      assert_prep_branch_deleted_for(pull)
    end

    test "a PR is enqueued, the checks run with ruleset workflow, and the PR is merged" do
      pull, entry = enqueue_pull_request!(ref_name: "cr-line-endings")

      invoke_merge_queue_job!

      assert_entry_hook_delivered(entry, "checks_requested")

      head_sha = entry.head_sha
      check_suite = @check_suites[head_sha] ||= create(:check_suite, repository: @repo, head_sha:)

      workflow = Actions::Workflow.new(name: "required ci", path: ".github/workflows/ruleset.yml", imposer_repository_id: 1234, repository_id: @repo.id)
      workflow.save
      workflow.reload
      workflow_run = Actions::WorkflowRun.new(name: "required ci", workflow: workflow, workflow_file_checkout_sha: "0c13a9ed47b07feeb76d1749bdedf1f61e9d6762", check_suite: check_suite, repository: @repo, actor: @user)
      workflow_run.save

      conclusion = :success
      display_name = "required-run"

      if run = CheckRun.find_by(check_suite:, display_name:)
        run.update(conclusion:)
      else
        create(:check_run, conclusion, check_suite:, display_name:)
      end

      # It should not queue a job in the future because everything settled.
      MergeQueues.expects(:delayed_execute!).never

      invoke_merge_queue_job!

      assert_queue_size 0

      assert pull.merged?
      assert_pull_request_hook_delivered(pull, "dequeued")

      assert entry.destroyed?
      assert_entry_hook_delivered(entry, "destroyed")
      assert_prep_branch_merged_for(pull)
      assert_prep_branch_created_for(pull)
      assert_prep_branch_deleted_for(pull)
    end

    test "a PR is enqueued, the checks report failure, and the PR is ejected" do
      pull, entry = enqueue_pull_request!(ref_name: "cr-line-endings")

      invoke_merge_queue_job!

      assert_entry_hook_delivered(entry, "checks_requested")

      simulate_check(entry, :failure)

      invoke_merge_queue_job!

      assert_queue_size 0

      refute pull.merged?
      assert_pull_request_hook_delivered(pull, "dequeued")

      assert entry.destroyed?
      refute_prep_branch_merged_for(pull)
      assert_prep_branch_created_for(pull)
      assert_prep_branch_deleted_for(pull)
      assert_entry_hook_delivered(entry, "destroyed")
    end

    test "a PR is enqueued, the checks times out, and the PR is ejected" do
      pull, entry = enqueue_pull_request!(ref_name: "cr-line-endings")

      invoke_merge_queue_job!

      assert_entry_hook_delivered(entry, "checks_requested")

      simulate_check(entry, :pending)
      entry.update(checks_requested_at: 2.hours.ago)
      invoke_merge_queue_job!

      assert_queue_size 0

      refute pull.merged?
      assert_pull_request_hook_delivered(pull, "dequeued")

      assert entry.destroyed?
      refute_prep_branch_merged_for(pull)
      assert_prep_branch_created_for(pull)
      assert_prep_branch_deleted_for(pull)
      assert_entry_hook_delivered(entry, "destroyed")
    end

    test "a PR is enqueued, there are no required checks, and the PR is merged" do
      pull, entry = enqueue_pull_request!(ref_name: "cr-line-endings")

      # Remove all required checks.
      @queue.protected_branch.required_status_checks_enforcement_level = :off
      @queue.protected_branch.required_status_checks.destroy_all
      @queue.protected_branch.save!

      invoke_merge_queue_job!

      assert_queue_size 0

      assert pull.merged?
      assert_pull_request_hook_delivered(pull, "dequeued")

      assert_prep_branch_merged_for(pull)
      assert_prep_branch_created_for(pull)
      assert_prep_branch_deleted_for(pull)
      refute_entry_hook_delivered(entry, "checks_requested")

      # TODO: This is a bug! We shouldn't send a `destroyed` event if we never sent a checks requested.
      # refute_entry_hook_delivered(entry, "destroyed")
    end

    test "a PR is enqueued, branch protection rules change, and the PR is ejected" do
      pull, entry = enqueue_pull_request!(ref_name: "cr-line-endings")

      invoke_merge_queue_job!

      # Add new rule for requiring review threads to be resolved.
      @queue.protected_branch.tap(&:enable_required_review_thread_resolution).save

      # Add a review comment that must be resolved.
      create(:user) do |reviewer|
        @repo.add_member(reviewer, action: :write)
        create(:pull_request_review_comment, pull_request: pull, user: reviewer) do |comment|
          create(:pull_request_review, :commented,
            pull_request: pull,
            user: reviewer,
            review_comments: [comment],
            review_threads: [comment.pull_request_review_thread])
          comment.submit!
        end
      end

      simulate_check(entry, :success)

      invoke_merge_queue_job!

      if GitHub.flipper[:mq_dont_send_duplicate_destroyed_webhooks].enabled?
        refute_dogstats_increment("merge_queue.duplicate_webhook_dispatch", tags: ["type:MergeQueues::WebHook::Destroyed"])
      else
        assert_dogstats_increment("merge_queue.duplicate_webhook_dispatch", tags: ["type:MergeQueues::WebHook::Destroyed"])
      end

      assert_queue_size 0

      refute pull.merged?
      assert_pull_request_hook_delivered(pull, "dequeued")

      assert entry.destroyed?
      assert_entry_hook_delivered(entry, "destroyed")
      refute_prep_branch_merged_for(pull)
      assert_prep_branch_created_for(pull)
      assert_prep_branch_deleted_for(pull)
    end

    context "rules engine" do
      test "a PR is enqueued, the checks pass, and the PR is merged" do
        create(
          :repository_ruleset,
          source: @repo,
          rule_configurations: [
            build(
              :repository_rule_configuration,
              :required_status_checks,
              strict: false,
              contexts: ["rules-only"],
            ),
          ],
          conditions: [
            build(
              :repository_rule_condition,
              :targets_branch,
              branch_name: "refs/heads/#{@queue.branch}",
            ),
          ],
        )

        pull, entry = enqueue_pull_request!(ref_name: "cr-line-endings")

        invoke_merge_queue_job!

        simulate_check(entry, :success)
        simulate_check(entry, :pending, "rules-only")

        invoke_merge_queue_job!

        # Still awaiting required checks, validate it's not been removed.
        refute entry.destroyed?

        simulate_check(entry, :success, "rules-only")

        invoke_merge_queue_job!

        assert_queue_size 0

        assert pull.merged?
        assert_pull_request_hook_delivered(pull, "dequeued")

        assert entry.destroyed?
        assert_entry_hook_delivered(entry, "destroyed")
        assert_prep_branch_merged_for(pull)
        assert_prep_branch_created_for(pull)
        assert_prep_branch_deleted_for(pull)
      end
    end

    context "ALL_GREEN strategy" do
      test "multiple PRs are enqueued, a PR transitions to an invalid state, and the PR is ejected and others merged" do
        pull_1, entry_1 = enqueue_pull_request!(ref_name: "cr-line-endings")
        pull_2, entry_2 = enqueue_pull_request!
        pull_3, entry_3 = enqueue_pull_request!

        # Simulate a bad head for the Pull Request.
        entry_2.update(enqueued_head_sha: "deadbeef")

        invoke_merge_queue_job!

        assert_entry_hook_delivered(entry_1, "checks_requested")
        refute_entry_hook_delivered(entry_2, "checks_requested")
        assert_entry_hook_delivered(entry_3, "checks_requested")

        simulate_check(entry_1, :success)
        simulate_check(entry_3, :success)

        invoke_merge_queue_job!

        assert_queue_size 0

        # Valid PRs are merged.
        [[pull_1, entry_1], [pull_3, entry_3]].each do |(pull, entry)|
          assert pull.merged?
          assert_pull_request_hook_delivered(pull, "dequeued")

          assert entry.destroyed?
          assert_entry_hook_delivered(entry, "destroyed")
        end

        # A single push is performed for the first and last PR.
        assert_prep_branch_merged_for(pull_3)
        assert_prep_branch_created_for(pull_3)
        assert_prep_branch_deleted_for(pull_3)

        # Invalid PR is ejected.
        refute pull_2.merged?
        assert_pull_request_hook_delivered(pull_2, "dequeued")

        # Invalid git state prevents temporary ref creation.
        assert entry_2.destroyed?
        refute_entry_hook_delivered(entry_2, "destroyed")
        refute_prep_branch_merged_for(pull_2)
        refute_prep_branch_created_for(pull_2)
        refute_prep_branch_deleted_for(pull_2)
      end

      test "multiple PRs are enqueued, a PR has a merge conflict, and the PR is ejected without unnecessary builds" do
        pull_1, entry_1 = enqueue_pull_request!(ref_name: "cr-line-endings")

        pull_2, entry_2 = enqueue_pull_request! do |ref|
          ref.append_commit({ message: "introducing a conflict", committer: @user }, @user) do |files|
            files.add("a", "this is now a conflict")
          end
        end

        pull_3, entry_3 = enqueue_pull_request!

        invoke_merge_queue_job!

        assert_equal MergeQueues::Entry::State::Unmergeable, entry_2.entry_state

        simulate_check(entry_1, :success)

        # Because something is remaining in the queue, we should schedule another execution in the future.
        MergeQueues.expects(:delayed_execute!).once

        assert_no_changes -> { entry_3.base_sha } do
          invoke_merge_queue_job!
        end

        assert_entry_hook_delivered(entry_1, "checks_requested")
        refute_entry_hook_delivered(entry_2, "checks_requested")
        assert_entry_hook_delivered(entry_3, "checks_requested")

        assert pull_1.merged?
        assert_pull_request_hook_delivered(pull_1, "dequeued")

        assert entry_1.destroyed?
        assert_entry_hook_delivered(entry_1, "destroyed")
        assert_prep_branch_merged_for(pull_1)
        assert_prep_branch_created_for(pull_1)
        assert_prep_branch_deleted_for(pull_1)

        refute pull_2.merged?
        assert entry_2.destroyed?
        assert_pull_request_hook_delivered(pull_2, "dequeued")
        refute_entry_hook_delivered(entry_2, "destroyed")
        refute_prep_branch_merged_for(pull_2)
        refute_prep_branch_created_for(pull_2)
        refute_prep_branch_deleted_for(pull_2)

        refute pull_3.merged?
        refute entry_3.destroyed?

        # Validate the git tree has not broken.
        assert_equal entry_1.head_sha, entry_3.base_sha

        refute_pull_request_hook_delivered(pull_3, "dequeued")
        refute_entry_hook_delivered(entry_3, "destroyed")
        refute_prep_branch_merged_for(pull_3)
        assert_prep_branch_created_for(pull_3)
        refute_prep_branch_deleted_for(pull_3)
      end
    end

    test "a PR is added to the queue, a PR jumps the queue, and the prep branches are regenerated" do
      pull_1, entry_1 = enqueue_pull_request!(ref_name: "cr-line-endings")

      invoke_merge_queue_job!

      pull_2, entry_2 = enqueue_pull_request!(jump: true)

      invoke_merge_queue_job!

      assert_prep_branch_created_for(pull_1, count: 2)
      assert_entry_hook_delivered(entry_1, "destroyed")
      assert_entry_hook_delivered(entry_1, "checks_requested", count: 2)

      assert_prep_branch_created_for(pull_2)
      assert_entry_hook_delivered(entry_2, "checks_requested")
    end

    context "HEAD_GREEN strategy" do
      test "PRs are enqueued and history is out of order, the checks pass, and the head PR is merged" do
        Spokesd.enable_spokesd

        @queue.update(merging_strategy: IConfiguration::GroupingStrategy::HeadGreen.serialize)

        # Simulate a stacked PR commit tree.
        @repo.refs.create("refs/heads/forked-cr-line-endings", @repo.ref_to_sha("cr-line-endings"), @user).tap do |ref|
          ref.append_commit({ message: "WIP", committer: @user }, @user) do |files|
            files.add("a", "this may conflict, y'all")
          end
        end

        pull_1, entry_1 = enqueue_pull_request!(ref_name: "forked-cr-line-endings")
        pull_2, entry_2 = enqueue_pull_request!
        pull_3, entry_3 = enqueue_pull_request!(ref_name: "cr-line-endings")
        pull_4, entry_4 = enqueue_pull_request!

        invoke_merge_queue_job!

        simulate_check(entry_4, :success)

        invoke_merge_queue_job!(sync_prs: true)

        # Stacked PRs are implicitly merged by the `SynchronizePullRequestJob`.
        assert pull_3.merged?
        assert_pull_request_hook_delivered(pull_3, "dequeued")

        # The entry will have a failing ref creation.
        assert entry_3.destroyed?
        refute_entry_hook_delivered(entry_3, "checks_requested")
        refute_entry_hook_delivered(entry_3, "destroyed")

        [pull_1, pull_2, pull_4].each do |pull|
          assert pull.merged?
          assert_pull_request_hook_delivered(pull, "dequeued")
        end

        # The first two entries are valid and implicitly merged.
        [[pull_1, entry_1], [pull_2, entry_2]].each do |(pull, entry)|
          assert entry.destroyed?
          refute_prep_branch_merged_for(pull)
          assert_prep_branch_created_for(pull)
          assert_prep_branch_deleted_for(pull)
          assert_entry_hook_delivered(entry, "destroyed")
        end

        # The last entry is valid and merged.
        assert entry_4.destroyed?
        assert_prep_branch_merged_for(pull_4)
        assert_prep_branch_created_for(pull_4)
        assert_prep_branch_deleted_for(pull_4)
        assert_entry_hook_delivered(entry_4, "destroyed")
      end
    end

    test "losing access to the queue triggers a full clear" do
      # Simulate in flight queue.
      pull, entry = enqueue_pull_request!(ref_name: "cr-line-endings")
      invoke_merge_queue_job!

      # Prevent the queue from operating if the user loses access and run it.
      Repository.any_instance.stubs(:merge_queue_enabled?).returns(false)

      invoke_merge_queue_job!

      # Queue should have been cleared.
      refute pull.merged?
      assert_queue_size 0
      refute MergeQueue.exists?(@queue.id), "the queue should have been deleted"
      refute @queue.queue_ref_collection.find(entry.head_ref), "the queue did not clean up all the pending refs"

      # Webhooks delivered for the various entities.
      assert_pull_request_hook_delivered(pull, "dequeued")
    end

    test "pull requests cannot be enqueued using temp branches" do
      pull, entry = enqueue_pull_request!(ref_name: "cr-line-endings")
      invoke_merge_queue_job!

      pull = PullRequest.create_for(@repo,
        base: @queue.branch,
        head: entry.qualified_head_ref,
        user: @user,
        title: "title",
        body: "body",
      )

      assert_includes pull.errors.full_messages, "Head must not be a merge queue branch"
    end

    MergeQueue::ALLOWED_MERGE_METHODS.each do |merge_method|
      context merge_method do
        test "merge queue ref updates are correct in the search index" do
          @queue.update(merge_method:)

          pull_1, entry_1 = enqueue_pull_request!(ref_name: "cr-line-endings")
          pull_2, entry_2 = enqueue_pull_request! do |ref|
            ref.append_commit({ message: "commit #1", committer: @user }, @user) do |files|
              files.add(Faker::File.file_name, SecureRandom.hex(32))
            end

            ref.append_commit({ message: "commit #2", committer: @user }, @user) do |files|
              files.add(Faker::File.file_name, SecureRandom.hex(32))
            end
          end

          invoke_merge_queue_job!



          # Find all the PR#2 commits contained within the "entry_2" prep branch graph.
          commits = [].tap do |commits|
            commit = @queue.queue_ref_collection.find(entry_2.head_ref).commit

            while commit.present? && commit.oid != entry_1.head_sha
              commits << commit
              commit = @repo.commits.find(@repo.commits.find(commit.oid).first_parent_oid)
            end
          end

          # Continue with merge queue execution.
          [entry_1, entry_2].each { |entry| simulate_check(entry, :success) }
          invoke_merge_queue_job!

          linked_pull_request_ids = pull_2.linked_commit_ids

          commits.each do |commit|
            assert_includes linked_pull_request_ids, commit.oid, "commit missing from search index"
          end
        end
      end
    end
  end
end
