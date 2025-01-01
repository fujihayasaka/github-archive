# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class ProtectedBranchMergeQueueTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  Spokesd.share_spokesdb(self)

  fixtures do
    Spokesd.enable_spokesd
    make_trusted_oauth_apps_owner
    create(:merge_queue_integration)

    @repo = create(:repository, :has_merge_queue)
    @user = create(:user)
    @repo.add_member @user, action: :write

    @queue = @repo.default_merge_queue
    @protected_branch = @queue.protected_branch
    @protected_branch.required_status_checks_enforcement_level = :non_admins
    @protected_branch.pull_request_reviews_enforcement_level = :off
    @protected_branch.required_status_checks.create! context: "required-run"
    @protected_branch.save!

    @pull = PullRequest.create_for!(@repo,
      base: @protected_branch.name,
      head: "cr-line-endings",
      user: @user,
      title: "title",
      body: "body",
    )

    create(:check_run, :success,
      check_suite: create(:check_suite, repository: @repo, head_sha: @pull.head_sha),
      display_name: "required-run",
    )

    example_repo_snapshot
  end

  setup do
    Spokesd.enable_spokesd
    skip unless GitHub.merge_queues_enabled?
    GitHub.flipper[:merge_queue].enable(@repo)
    example_repo_restore
  end

  context "allow when"  do
    test "ref update is the same as MergeQueueEntry head_sha" do
      @pull.create_merge_commit
      @queue.enqueue!(pull_request: @pull, enqueuer: @user)

      MergeQueues::Service::Tick.new(@repo, @queue.branch).call

      entry = @queue.entries.first
      ref = @queue.reload.queue_ref_collection.find(entry.head_ref)

      refute_nil ref

      ref_update = create_branch_update(
        @repo,
        name: @repo.default_branch,
        before_oid: @queue.branch_head_oid,
        after_oid: entry.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
    end

    test "ref update for a branch with the merge queue turned off" do
      GitHub.flipper[:merge_queue].disable(@repo)
      @repo.protect_branch("-gh-pages", creator: @user, entry_point: :test_case)

      pull = PullRequest.create_for!(@repo,
        base: "-gh-pages",
        head: "cr-line-endings",
        user: @user,
        title: "title",
        body: "body",
      )

      pull.create_merge_commit

      ref_update = create_branch_update(
        @repo,
        name: "-gh-pages",
        before_oid: @repo.heads["-gh-pages"].target_oid,
        after_oid: pull.merge_commit_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
    end

    test "PR is enqueued by an authorized user who then loses authorization" do
      # Grant repo :write authorization to both user and enqueuer, but only branch writable by the enqueuer
      enqueuer = create(:user, login: "enqueuer")

      # if we add more tests on orgs, we should move this out into the fixture
      org = create(:business_plus_organization)
      org_repo = create(:repository, :has_merge_queue, owner: org)
      queue = org_repo.default_merge_queue
      protected_branch = queue.protected_branch
      protected_branch.required_status_checks_enforcement_level = :off
      protected_branch.pull_request_reviews_enforcement_level = :off
      protected_branch.save!

      org_repo.add_member enqueuer, action: :write
      org_repo.add_member @user, action: :write
      protected_branch.replace_authorized_actors(user_ids: [enqueuer.id], team_ids: [], entry_point: :test_case)

      assert protected_branch.authorized?(enqueuer)
      refute protected_branch.authorized?(@user)

      pull = PullRequest.create_for!(org_repo,
        base: protected_branch.name,
        head: "cr-line-endings",
        user: @user,
        title: "title",
        body: "body",
      )

      pull.create_merge_commit

      merge_queue = protected_branch.merge_queue
      refute_nil merge_queue, "expected protected branch to have a merge queue"
      merge_queue.enqueue!(pull_request: pull, enqueuer: enqueuer)

      # Enable deploy-then-merge, so the queue engine will mark the
      # entry as mergeable, but not actually merge it.
      org_repo.enable_feature(:merge_queue_deploy_then_merge)
      MergeQueues::Service::Tick.new(org_repo, merge_queue.branch).call

      entry = merge_queue.entries.first
      assert_predicate entry, :valid?
      assert_predicate entry, :mergeable?

      # remove branch authorization for the enqueuing user and grant it to @user instead
      protected_branch.replace_authorized_actors(user_ids: [@user.id], team_ids: [], entry_point: :test_case)
      assert protected_branch.authorized?(@user)
      refute protected_branch.authorized?(enqueuer)

      ref_update = create_branch_update(
        org_repo,
        name: org_repo.default_branch,
        before_oid: org_repo.heads[org_repo.default_branch].target_oid,
        after_oid: entry.head_sha,
      )

      # @user should be authorized to merge
      decision = RuleEngine::Evaluator.evaluate_rules_one(org_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
    end
  end

  context "deny when" do
    test "ref update is not a valid MergeQueueEntry head_sha" do
      @pull.create_merge_commit
      @queue.enqueue!(pull_request: @pull, enqueuer: @user)

      MergeQueues::Service::Tick.new(@repo, @queue.branch).call

      entry = @queue.entries.first

      refute_nil entry

      ref = @queue.reload.queue_ref_collection.find(entry.head_ref)

      refute_nil ref

      ref_update = create_branch_update(
        @repo,
        name: @repo.default_branch,
        before_oid: @queue.branch_head_oid,
        after_oid: entry.base_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
    end

    test "merge is attempted outside of the queue and ref is not in the queue" do
      @pull.create_merge_commit

      ref_update = create_branch_update(
        @repo,
        name: @repo.default_branch,
        before_oid: @queue.branch_head_oid,
        after_oid: @pull.merge_commit_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      assert_equal "merge_queue", decision.failed_rule_types.first
    end

    test "merge is attempted outside of the queue and ref is in the queue" do
      @pull.create_merge_commit
      @queue.enqueue!(pull_request: @pull, enqueuer: @user)

      ref = @repo.heads.find(@pull.head_ref)
      merge_commit, _, _ = ref.repository.commits.create_merge_commit(@user, @pull.base_ref, @pull.head_ref)

      ref_update = create_branch_update(
        @repo,
        name: @repo.default_branch,
        before_oid: @queue.branch_head_oid,
        after_oid: merge_commit.oid
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      assert_equal "merge_queue", decision.failed_rule_types.first
    end

    test "push to add a commit if ref is already in the queue" do
      @pull.create_merge_commit
      @queue.enqueue!(pull_request: @pull, enqueuer: @user)

      ref = @repo.heads.find(@pull.head_ref)
      metadata = { message: "new commit", committer: @user }
      new_commit = ref.repository.commits.create(metadata, ref.target_oid) do |files|
        files.add("new_file.rb", "really amazing content")
      end

      ref_update = create_branch_update(
        @repo,
        name: @pull.head_ref,
        before_oid: @queue.branch_head_oid,
        after_oid: new_commit.oid
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      assert_equal "merge_queue_locked_ref", decision.failed_rule_types.first
    end

    test "there are no reviews for a non merge queue update" do
      @protected_branch.merge_queue_enforcement_level = :everyone
      @protected_branch.pull_request_reviews_enforcement_level = :everyone
      @protected_branch.save!

      @pull.create_merge_commit

      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Pull request At least 1 approving review is required by reviewers with write access.") do
        @queue.enqueue!(pull_request: @pull, enqueuer: @user)
      end

      ref_update = create_branch_update(
        @repo,
        name: @repo.default_branch,
        before_oid: @repo.default_oid,
        after_oid: @pull.merge_commit_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?

      run = decision.runs_by_rule_type(:pull_request).find(&:failed?)
      assert run.present?
      assert_equal "At least 1 approving review is required by reviewers with write access.", run&.message
    end

    test "there are no reviews for a merge queue update but normal merging is enabled" do
      @protected_branch.merge_queue_enforcement_level = :everyone
      @protected_branch.pull_request_reviews_enforcement_level = :everyone
      @protected_branch.save!

      @pull.create_merge_commit

      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Pull request At least 1 approving review is required by reviewers with write access.") do
        @queue.enqueue!(pull_request: @pull, enqueuer: @user)
      end

      ref_update = create_branch_update(
        @repo,
        name: @repo.default_branch,
        before_oid: @repo.default_oid,
        after_oid: @pull.merge_commit_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?

      run = decision.runs_by_rule_type(:pull_request).find(&:failed?)
      assert run.present?
      assert_equal "At least 1 approving review is required by reviewers with write access.", run&.message
    end
  end

  context "admin override" do
    test "allows for admin to merge when ref is not in the queue" do
      @protected_branch.merge_queue_enforcement_level = :non_admins
      @protected_branch.save!

      @pull.create_merge_commit
      ref_update = create_branch_update(
        @repo,
        name: @repo.default_branch,
        before_oid: @queue.branch_head_oid,
        after_oid: @pull.merge_commit_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

      refute_predicate decision, :rules_fulfilled?
      assert decision.can_bypass_rule_type?(:merge_queue)
      assert decision.action_permitted?
    end

    test "denies admin to merge when ref is in the queue" do
      @protected_branch.merge_queue_enforcement_level = :non_admins
      @protected_branch.save!

      @pull.create_merge_commit
      @queue.enqueue!(pull_request: @pull, enqueuer: @user)

      ref_update = create_branch_update(
        @repo,
        name: @repo.default_branch,
        before_oid: @queue.branch_head_oid,
        after_oid: @pull.merge_commit_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

      refute_predicate decision, :rules_fulfilled?
      refute decision.can_bypass_rule_type?(:merge_queue)
      refute decision.action_permitted?
    end

    test "denies admin to merge when ref is not in the queue and include administrators is turned on" do
      @protected_branch.merge_queue_enforcement_level = :everyone
      @protected_branch.save!

      @pull.create_merge_commit
      ref_update = create_branch_update(
        @repo,
        name: @repo.default_branch,
        before_oid: @queue.branch_head_oid,
        after_oid: @pull.merge_commit_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

      refute_predicate decision, :rules_fulfilled?
      refute decision.can_bypass_rule_type?(:merge_queue)
      refute decision.action_permitted?
    end

    test "denies admin to merge when ref is in the queue and include administrators is turned on" do
      @protected_branch.merge_queue_enforcement_level = :everyone
      @protected_branch.save!

      @pull.create_merge_commit
      @queue.enqueue!(pull_request: @pull, enqueuer: @user)

      ref_update = create_branch_update(
        @repo,
        name: @repo.default_branch,
        before_oid: @queue.branch_head_oid,
        after_oid: @pull.merge_commit_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

      refute_predicate decision, :rules_fulfilled?
      refute decision.can_bypass_rule_type?(:merge_queue)
      refute decision.action_permitted?
    end
  end
end
