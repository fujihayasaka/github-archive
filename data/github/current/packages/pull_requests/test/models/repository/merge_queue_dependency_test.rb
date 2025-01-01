# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryMergeQueueDependencyTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    create(:merge_queue_integration)

    @viewer = create(:user, login: "viewer")
    @contributor = create(:user, login: "contributor")
    @repo = create(:repository, from_example: :simple)
    GitHub.flipper[:merge_queue].enable(@repo)
    @repo.add_member @contributor, action: :write

    ref = @repo.heads.find(@repo.default_branch)
    @feature_branch = @repo.heads.create("feature-branch", ref.target, @contributor).freeze

    @merge_queue = create(:merge_queue, repository: @repo)
    create(:merge_queue_entry, queue: @merge_queue)
  end

  context "#can_add_pull_requests_to_merge_queue?" do
    if GitHub.merge_queues_enabled?
      test "returns true for user with repo write access" do
        assert @repo.can_add_pull_requests_to_merge_queue?(@contributor)
      end

      test "returns false for user with less than write access" do
        refute @repo.can_add_pull_requests_to_merge_queue?(@viewer)
      end

      test "returns false for anonymous user" do
        refute @repo.can_add_pull_requests_to_merge_queue?(nil)
      end

      test "returns false when non-protected branch name is given" do
        refute @repo.can_add_pull_requests_to_merge_queue?(@contributor, branch_name: @feature_branch.name)
      end

      test "returns false when protected branch name is given but it doesn't have a merge queue" do
        create(:protected_branch, repository: @repo, name: @feature_branch.name, creator: @repo.owner,
          required_status_checks_enforcement_level: :off, pull_request_reviews_enforcement_level: :everyone)

        refute @repo.can_add_pull_requests_to_merge_queue?(@contributor, branch_name: @feature_branch.name)
      end

      test "returns true when branch name is given and it's a protected branch with a merge queue" do
        assert @repo.can_add_pull_requests_to_merge_queue?(@contributor, branch_name: @merge_queue.branch)
      end
    else
      test "returns false when merge queues are disabled" do
        refute @repo.can_add_pull_requests_to_merge_queue?(@contributor)
        refute @repo.can_add_pull_requests_to_merge_queue?(@viewer)
        refute @repo.can_add_pull_requests_to_merge_queue?(nil)
        refute @repo.can_add_pull_requests_to_merge_queue?(@contributor, branch_name: @merge_queue.branch)
      end
    end
  end

  if GitHub.merge_queues_enabled?
    context "merge_queues association" do
      test "destroys merge queues when repo is destroyed" do
        assert_difference -> { MergeQueue.count }, -1 do
          @repo.destroy
        end
      end

      test "destroys merge queue entries when repo is destroyed" do
        assert_difference -> { MergeQueueEntry.count }, -1 do
          perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
            @repo.destroy
          end
        end
      end
    end
  end

  context "#default_merge_queue" do
    test "returns the merge queue associated with the default branch" do
      queue = @repo.default_merge_queue

      assert_equal @repo.default_branch, queue.branch
    end
  end

  context "#merge_queue_for" do
    test "finds the queue for the given branch" do
      assert_no_difference -> { MergeQueue.count } do
        @repo.merge_queue_for(branch: "foo")
        @repo.async_merge_queue_for(branch: "foo").sync
      end
    end

    test "avoids SQL query when merge queues relation is already loaded" do
      repo2 = create(:repository, from_example: :simple)
      GitHub.flipper[:merge_queue].enable(repo2)
      merge_queue2 = create(:merge_queue, repository: repo2)

      repos = [@repo, repo2]
      GitHub::PrefillAssociations.prefill_associations(repos, :merge_queues)

      assert_query_count(0) do
        assert_equal @merge_queue, @repo.merge_queue_for(branch: @merge_queue.branch)
        assert_equal merge_queue2, repo2.merge_queue_for(branch: merge_queue2.branch)
      end
    end

    test "sync and async methods return the same result" do
      # Branch with merge queue
      refute_nil @repo.merge_queue_for(branch: @repo.default_branch)
      assert_merge_queue_for(repo: @repo, branch: @repo.default_branch)

      # Branch without merge queue
      protected_branch = create(:protected_branch, repository: @repo, name: "dev")
      assert_nil_merge_queue_for(repo: @repo, branch: protected_branch.name)

      # Non-existent branch
      assert_nil_merge_queue_for(repo: @repo, branch: "fake-branch")
    end
  end

  context "#merge_queue_enabled?" do
    if GitHub.enterprise?
      test "always returns true on GHES" do
        repo = build_stubbed(:repository)

        assert_predicate repo, :merge_queue_enabled?
      end
    else
      test "returns true if the repository owner's plan supports the merge queue" do
        owner = build_stubbed(:business_plus_org)
        repo = build_stubbed(:repository, :private, owner:)
        repo.network = build_stubbed(:repository_network, root: repo)

        assert_predicate repo, :merge_queue_enabled?
      end

      test "returns false if the repository owner's plan does not support the merge queue and they were not part of the private beta" do
        owner = build_stubbed(:team_org)
        repo = build_stubbed(:repository, :private, owner:)
        repo.network = build_stubbed(:repository_network, root: repo)

        refute_predicate repo, :merge_queue_enabled?
      end

      test "returns true if the repository owner's plan does not support the merge queue but they were part of the private beta" do
        owner = build_stubbed(:team_org)
        repo = build_stubbed(:repository, :private, owner:)
        repo.network = build_stubbed(:repository_network, root: repo)
        GitHub.flipper[:merge_queue].enable(repo)

        assert_predicate repo, :merge_queue_enabled?
      end
    end
  end

  context "#merge_queue_enabled_for_branch?" do
    if GitHub.merge_queues_enabled?
      test "returns false if repo does not have access to merge queues" do
        Repository.any_instance.stubs(:merge_queue_enabled?).returns(false)
        @repo.protect_branch(@repo.default_branch,
          creator: @repo.owner,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )

        refute @repo.merge_queue_enabled_for_branch?(@repo.default_branch)
      end

      test "returns false if the branch is not protected" do
        GitHub.flipper[:merge_queue].enable(@repo)
        @repo.protected_branches.destroy_all

        refute @repo.merge_queue_enabled_for_branch?(@repo.default_branch)
      end

      test "returns false if the branch is protected but merge queue not enabled" do
        GitHub.flipper[:merge_queue].enable(@repo)
        @repo.protect_branch(@repo.default_branch,
          creator: @repo.owner,
          enforce_merge_queue: false,
          entry_point: :test_case,
        )

        refute @repo.merge_queue_enabled_for_branch?(@repo.default_branch)
      end

      test "returns true if the branch is protected and merge queue is enabled" do
        GitHub.flipper[:merge_queue].enable(@repo)
        @repo.protect_branch(@repo.default_branch,
          creator: @repo.owner,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )

        assert @repo.merge_queue_enabled_for_branch?(@repo.default_branch)
      end

      test "returns true if multiple branch protections exist and one has the queue enabled" do
        GitHub.flipper[:merge_queue].enable(@repo)
        @repo.protect_branch("#{@repo.default_branch}*",
          creator: @repo.owner,
          enforce_merge_queue: false,
          entry_point: :test_case,
        )

        @repo.protect_branch(@repo.default_branch,
          creator: @repo.owner,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )

        assert @repo.merge_queue_enabled_for_branch?(@repo.default_branch)
      end

      test "returns false when no merge queue exists for the protected branch" do
        GitHub.flipper[:merge_queue].enable(@repo)
        @repo.protect_branch(@repo.default_branch,
          creator: @repo.owner,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )
        merge_queue = @repo.merge_queue_for(branch: @repo.default_branch)
        merge_queue&.delete
        refute @repo.merge_queue_enabled_for_branch?(@repo.default_branch)
      end
    else
      test "returns false for enterprise" do
        GitHub.flipper[:merge_queue].enable(@repo)
        @repo.protect_branch(@repo.default_branch,
          creator: @repo.owner,
          enforce_merge_queue: true,
          entry_point: :test_case,
        )

        refute @repo.merge_queue_enabled_for_branch?(@repo.default_branch)
      end
    end
  end

  context "#merge_queue_commits_include?" do
    if GitHub.merge_queues_enabled?
      test "returns false if passed commit_id is null" do
        refute @repo.merge_queue_commits_include?(GitHub::NULL_OID)
      end

      test "returns true if passed the head SHA of a queue entry" do
        entry = create(:merge_queue_entry, queue: @merge_queue, head_sha: SecureRandom.hex(16))

        assert @repo.merge_queue_commits_include?(entry.head_sha)
      end
    end
  end

  def assert_merge_queue_for(repo:, branch:)
    assert_equal repo.merge_queue_for(branch: branch), repo.async_merge_queue_for(branch: branch).sync
  end

  def assert_nil_merge_queue_for(repo:, branch:)
    assert_nil repo.merge_queue_for(branch: branch)
    assert_nil repo.async_merge_queue_for(branch: branch).sync
  end
end
