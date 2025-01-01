# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMergeQueueDependencyTest < GitHub::TestCase

  fixtures do
    @entry = create(:merge_queue_entry)
    @pr = @entry.pull_request
    @protected_branch = @pr.base_branch_rule_evaluator&.original_protected_branch
    @repo = @pr.repository
    @repo_owner = @repo.owner
    @queue = @entry.queue

    make_trusted_oauth_apps_owner
    @integration = create(:merge_queue_integration)
  end

  setup do
    enable_feature_flag(:merge_queue)
  end

  context "#merge_queue" do
    test "can be loaded in bulk for many pull requests at once" do
      entry2 = create(:merge_queue_entry, queue: @queue)
      pr2 = entry2.pull_request
      entry3 = create(:merge_queue_entry)
      queue_for_entry3 = entry3.queue
      pr3 = entry3.pull_request
      entry4 = create(:merge_queue_entry)
      queue_for_entry4 = entry4.queue
      pr4 = entry4.pull_request
      pr_without_queue = create(:pull_request, :disable_disk_access)
      pull_requests = [@pr, pr2, pr3, pr4, pr_without_queue].map(&:reload) # make sure no relations are already loaded
      expected_queries = { merge_queues: 1, repositories: 1 }

      assert_query_count(expected_queries.values.sum) do
        assert_query_count_per_table(expected_queries) do
          GitHub::PrefillAssociations.prefill_batch_method(pull_requests, :merge_queue)
        end
      end

      assert_query_count(0, backtrace_lines: 10) do
        assert_equal @queue, @pr.merge_queue
        assert_equal @queue, pr2.merge_queue
        assert_equal queue_for_entry3, pr3.merge_queue
        assert_equal queue_for_entry4, pr4.merge_queue
        assert_nil pr_without_queue.merge_queue
      end
    end
  end

  context "#merge_queue_enabled?" do
    if GitHub.merge_queues_enabled?
      test "returns false when merge queue feature flag is disabled" do
        # MQ is unconditionally enabled for GHES repos
        skip if GitHub.enterprise?

        disable_feature_flag(:merge_queue)
        refute_predicate @pr, :merge_queue_enabled?
      end

      test "returns false when merge queue is disabled for the protected base branch of the pull request" do
        @protected_branch.update!(merge_queue_enforcement_level: :off)
        refute_predicate @pr, :merge_queue_enabled?
      end

      test "returns false when merge queue does not exist for the pull request's protected base branch" do
        @queue.delete
        refute_predicate @pr, :merge_queue_enabled?
      end

      test "returns true when pull request's base branch is protected with a merge queue and has merge queues enabled" do
        refute_equal :off, @protected_branch.merge_queue_enforcement_level
        assert_predicate @repo, :merge_queue_enabled?
        assert_predicate @pr, :merge_queue_enabled?
      end

      test "disabling the `require_merge_queue` rule via protected branches should delete the MergeQueue model" do
        assert_equal MergeQueue.count, 1
        @protected_branch.update!(merge_queue_enforcement_level: :off)
        refute_predicate @pr, :merge_queue_enabled?
        assert_nil @pr.merge_queue
        assert_equal MergeQueue.count, 0
      end

      test "avoids duplicate queries", skip_enterprise: true do
        assert_query_count_per_table({
          repositories: 1,
          users: 1,
          merge_queues: 1
        }) do
          @pr.merge_queue_enabled?
        end
      end

      test "doesn't refetch merge_queue when merge_queues relation is already loaded on the repo" do
        GitHub::PrefillAssociations.prefill_associations(@pr.repository, :merge_queues)

        assert_query_count_per_table({ merge_queues: 0 }) do
          @pr.merge_queue_enabled?
        end
      end
    else
      test "returns false when merge queues are globally disabled" do
        refute_predicate @pr, :merge_queue_enabled?
      end
    end
  end

  context "#protected_base_branch_merge_queue_enforced_for?" do
    if GitHub.merge_queues_enabled?
      test "returns true when base branch is protected and its merge queue is enforced for the given user" do
        repo_member = create(:user)
        @repo.add_member(repo_member)
        refute_predicate @protected_branch, :merge_queue_enforcement_level_off?

        assert @pr.protected_base_branch_merge_queue_enforced_for?(repo_member)
      end
    else
      test "returns false when merge queues are disabled" do
        repo_member = create(:user)
        @repo.add_member(repo_member)

        refute @pr.protected_base_branch_merge_queue_enforced_for?(repo_member)
      end
    end

    test "returns false when base branch is not protected" do
      repo = create(:repository, owner: @repo_owner, from_example: :renderables)
      pull = create(:pull_request, repository: repo, base_repository: repo, base_user: @repo_owner, base_ref: "box",
        head_repository: repo, head_user: @repo_owner, head_ref: "update_box")
      assert_nil pull.base_branch_rule_evaluator
      refute pull.protected_base_branch_merge_queue_enforced_for?(@repo_owner)
    end

    test "returns false when protected base branch's merge queue is not enforced for the given user" do
      @protected_branch.update!(merge_queue_enforcement_level: :non_admins)
      refute @pr.protected_base_branch_merge_queue_enforced_for?(@repo_owner)
    end
  end

  if GitHub.merge_queues_enabled?
    context "merge_queue_entries association" do
      test "destroys merge queue entry when pr is destroyed" do
        assert_difference -> { MergeQueueEntry.count }, -1 do
          @pr.destroy
        end
      end

      test "destroys merge queue entry when pr is closed via background job" do
        assert @queue.entry_for(pull_request: @pr)
        assert_difference -> { MergeQueueEntry.count }, -1 do
          @pr.close(@pr.user)
        end
        refute @queue.entry_for(pull_request: @pr)
      end
    end
  end
end

class PullRequestStatusAtCommitTest < GitHub::TestCase
  fixtures do
    skip unless GitHub.merge_queues_enabled?

    make_trusted_oauth_apps_owner
    create(:merge_queue_integration)

    queue = create(:merge_queue)
    repository = queue.repository
    @pull_request = create(
      :pull_request,
      :with_mergeable_head,
      repository:,
      user: repository.owner,
    )
    queue.enqueue!(pull_request: @pull_request, enqueuer: @pull_request.user)

    # Enable deploy-then-merge, so the queue engine will make a merge commit
    # for us, but not actually merge the entry.
    enable_feature_flag(:merge_queue_deploy_then_merge, repository)
    MergeQueues::Service::Tick.new(repository, queue.branch).call

    merge_queue_entry = queue.entries.first
    @merge_queue_entry_sha = merge_queue_entry.head_sha

    creator = repository.owner
    create(:status, repository:, creator:, sha: @merge_queue_entry_sha, context: "ci/janky", state: "pending")
    create(:status, repository:, creator:, sha: @merge_queue_entry_sha, context: "ci/janky", state: "success")

    check_suite = create(:check_suite, repository:, head_sha: @merge_queue_entry_sha)
    create(:completed_check_run, :success, check_suite:, name: "check_run1", created_at: 1.second.ago)
    create(:completed_check_run, :failure, check_suite:, name: "check_run2")

    create(:status, repository:, creator:, sha: @merge_queue_entry_sha, context: "continuous-integration/travis-ci/pr", state: "success")
    create(:status, repository:, creator:, sha: @merge_queue_entry_sha, context: "continuous-integration/travis-ci/push", state: "pending")
  end

  test "returns a CombinedStatus for each context at the specified commit" do
    combined_status = @pull_request.status_at_commit(@merge_queue_entry_sha)
    statuses = combined_status.status_checks
    assert_equal 5, statuses.size

    # Expected order is 1) statuses, by context, then 2) check runs, by name

    # statuses
    assert_equal "ci/janky", statuses[0].context
    assert_equal "success", statuses[0].state

    assert_equal "continuous-integration/travis-ci/pr", statuses[1].context
    assert_equal "success", statuses[1].state

    assert_equal "continuous-integration/travis-ci/push", statuses[2].context
    assert_equal "pending", statuses[2].state

    # check runs
    assert_equal "check_run1", statuses[3].name
    assert_equal "success", statuses[3].conclusion

    assert_equal "check_run2", statuses[4].name
    assert_equal "failure", statuses[4].conclusion
  end
end
