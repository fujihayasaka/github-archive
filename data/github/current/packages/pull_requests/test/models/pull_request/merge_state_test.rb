# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestMergeStateTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @source = create(:private_repository, owner: @owner, from_example: :pull_request_source)

    example_repo_snapshot

    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
  end

  setup do
    example_repo_restore
    @pull = PullRequest.create_for!(@source,
      title: "Sample pull request",
      base: "master",
      head: "master-forward-2",
      user: @owner)

    @pull.create_merge_commit
    @pull.reload
    GitHub.stubs(:launch_github_app).returns(@launch_app)
  end

  def make_status(pull, state, context = "default")
    create(:status, repository: pull.repository,
                creator: pull.repository.owner,
                state: state,
                sha: pull.head_sha,
                context: context)
  end

  # helper method to easily create commits for these tests
  def commit_hash(message: "Commit on master", committer: @owner)
    {
      message: message,
      committer: committer,
    }
  end

  test "merge_state is cached" do
    assert_equal @pull.cached_merge_state.object_id, @pull.cached_merge_state.object_id
  end

  test "reloading a PR resets merge state cache" do
    refute_equal @pull.cached_merge_state.object_id, @pull.reload.cached_merge_state.object_id
  end

  test "#status is :dirty for unmergeable pulls" do
    @pull.mergeable = false
    state = PullRequest::MergeState.new(@pull)
    assert_equal :dirty, state.status
    assert state.dirty?
    refute state.clean?
    refute state.unstable?
    refute state.unknown?
  end

  test "#status is :has_hooks for pulls in repos with hooks" do
    Repository.any_instance.stubs(:has_pre_receive_hooks?).returns(true)

    @pull.mergeable = true
    state = PullRequest::MergeState.new(@pull)
    assert_equal :has_hooks, state.status
    assert state.has_hooks?
    refute state.dirty?
    refute state.clean?
    refute state.unstable?
    refute state.unknown?
  end

  test "#status is :unknown for unchecked pulls (ie mergeable is nil)" do
    @pull.mergeable = nil
    state = PullRequest::MergeState.new(@pull)
    assert_equal :unknown, state.status
    assert state.unknown?
    refute state.clean?
    refute state.unstable?
    refute state.dirty?
  end

  test "#status is :clean for mergeable pulls with no status" do
    @pull.mergeable = true
    state = PullRequest::MergeState.new(@pull)
    assert_equal :clean, state.status
    assert state.clean?
    refute state.unknown?
    refute state.unstable?
    refute state.dirty?
  end

  test "#status is :unstable when pull has action_required check suites and Actions UI flag is enabled" do
    @pull.mergeable = true
    create(:check_suite_for_actions_app,
      :completed,
      repository: @pull.repository,
      head_sha: @pull.head_sha,
      conclusion: :action_required,
    )

    state = PullRequest::MergeState.new(@pull, viewer: @owner)
    assert_equal :unstable, state.status
    assert state.unstable?
    refute state.clean?
    refute state.unknown?
    refute state.dirty?
  end

  test "#status is :unstable for mergeable pulls with bad status" do
    @pull.mergeable = true
    make_status @pull, "error"

    state = PullRequest::MergeState.new(@pull)
    assert_equal :unstable, state.status
    assert state.unstable?
    refute state.clean?
    refute state.unknown?
    refute state.dirty?
  end

  test "#status is :unstable for mergeable pulls with bad status (even when the repo has hooks)" do
    Repository.any_instance.stubs(:has_pre_receive_hooks?).returns(true)
    @pull.mergeable = true
    make_status @pull, "error"

    state = PullRequest::MergeState.new(@pull)
    assert_equal :unstable, state.status
    assert state.unstable?
    refute state.clean?
    refute state.unknown?
    refute state.dirty?
  end

  test "status is :blocked when required signatures check is unsatisfied" do
    @pull.reload

    create(:protected_branch,
      name: @pull.base_ref_name,
      repository: @source,
      creator: @source.owner,
      signature_requirement_enforcement_level: :non_admins,
    )

    assert @pull.create_merge_commit

    state = PullRequest::MergeState.new(@pull, viewer: @owner)

    assert_predicate state, :blocked_by_required_signatures?
    assert_equal :blocked, state.status
  end

  context "require linear history" do
    test "status is :clean when the only protected branch policy violation is having merge commits" do
      create(:protected_branch,
        name: @pull.base_ref_name,
        repository: @source,
        creator: @source.owner,
        linear_history_requirement_enforcement_level: :everyone,
      )

      @pull.reload
      @pull.head_ref = @source.refs.find("master-merged-topic")

      assert @pull.create_merge_commit
      state = PullRequest::MergeState.new(@pull, viewer: @owner)

      failed_rule_types = state.rules_engine_evaluation_result.failed_rule_types

      assert_includes failed_rule_types, "required_linear_history"
      assert state.blocked_only_by_required_linear_history?
      assert_equal :clean, state.status
    end

    test "status is :unstable when the only protected branch policy violation is having merge commits and checks are pending" do
      create(:status, state: "pending", sha: @pull.head_sha, repository: @pull.repository, creator: @owner)
      create(:protected_branch,
        name: @pull.base_ref_name,
        repository: @source,
        creator: @source.owner,
        linear_history_requirement_enforcement_level: :everyone,
      )

      @pull.reload
      @pull.head_ref = @source.refs.find("master-merged-topic")

      assert @pull.create_merge_commit
      state = PullRequest::MergeState.new(@pull, viewer: @owner)

      failed_rule_types = state.rules_engine_evaluation_result.failed_rule_types

      assert_includes failed_rule_types, "required_linear_history"
      assert state.blocked_only_by_required_linear_history?
      assert_equal :unstable, state.status
    end

    test "allow admin override if linear history enforcement level is non-admin" do
      create(:protected_branch,
        name: @pull.base_ref_name,
        repository: @source,
        creator: @source.owner,
        linear_history_requirement_enforcement_level: :non_admins,
      )

      @pull.reload
      @pull.head_ref = @source.refs.find("master-merged-topic")

      assert @pull.create_merge_commit
      state = PullRequest::MergeState.new(@pull, viewer: @owner)

      failed_rule_types = state.rules_engine_evaluation_result.failed_rule_types

      assert_includes failed_rule_types, "required_linear_history"
      assert_equal :clean, state.status
      assert state.admin_override_possible?

      # additional test for when the viewer is a basic rando with no admin power
      basic_rando = create(:user)
      state = PullRequest::MergeState.new(@pull, viewer: basic_rando)
      assert_includes failed_rule_types, "required_linear_history"
      assert_equal :clean, state.status
      assert state.blocked_only_by_required_linear_history?
      refute state.admin_override_possible?
    end

    test "allow admin override if linear history is blocked by one ruleset but other rules are bypassable in another" do
      ruleset1 = create(:repository_ruleset, :repo_admin_bypass, source: @source)
      create(:repository_rule_configuration, rule_type: "update", parameters: { update_allows_fetch_and_merge: true }, repository_ruleset: ruleset1)
      create(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/#{@pull.base_ref_name}", repository_ruleset: ruleset1)

      ruleset2 = create(:repository_ruleset, source: @source)
      create(:repository_rule_configuration, rule_type: "required_linear_history", repository_ruleset: ruleset2)
      create(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/#{@pull.base_ref_name}", repository_ruleset: ruleset2)

      @pull.reload
      @pull.head_ref = @source.refs.find("master-merged-topic")

      assert @pull.create_merge_commit
      state = PullRequest::MergeState.new(@pull, viewer: @owner)

      failed_rule_types = state.rules_engine_evaluation_result.failed_rule_types

      assert_same_elements failed_rule_types, %w[required_linear_history update]
      assert_equal :blocked, state.status
      assert state.admin_override_possible?

      # additional test for when the viewer is a basic rando with no admin power
      basic_rando = create(:user)
      state = PullRequest::MergeState.new(@pull, viewer: basic_rando)
      assert_same_elements failed_rule_types, %w[required_linear_history update]
      assert_equal :blocked, state.status
      refute state.admin_override_possible?
    end

    test "allow admin override if merge method is blocked but bypassable" do
      ruleset1 = create(:repository_ruleset, :repo_admin_bypass, source: @source)
      create(:repository_rule_configuration, :pull_request, allowed_merge_methods: ["squash"], repository_ruleset: ruleset1)
      create(:repository_rule_condition, :targets_branch, branch_name: "refs/heads/#{@pull.base_ref_name}", repository_ruleset: ruleset1)

      @pull.reload
      @pull.head_ref = @source.refs.find("master-merged-topic")

      assert @pull.create_merge_commit
      state = PullRequest::MergeState.new(@pull, viewer: @owner, merge_method: :rebase)

      failed_rule_types = state.rules_engine_evaluation_result.failed_rule_types

      assert_same_elements failed_rule_types, %w[pull_request]
      assert_equal :blocked, state.status
      assert state.admin_override_possible?
    end
  end

  test "admin_override_possible? is false if draft?" do
    @pull.convert_to_draft(user: @source.owner)
    assert_predicate @pull, :draft?
    state = PullRequest::MergeState.new(@pull, viewer: @owner)

    refute_predicate state, :admin_override_possible?
  end

  test "#status is :blocked when required status checks are unsatisfied and pull is not behind" do
    protected_branch = @source.protect_branch(@pull.base_ref_name,
      creator: @source.owner,
      required_status_checks: { contexts: %w[ci/janky], include_admins: true },
      entry_point: :test_case,
    )

    state = PullRequest::MergeState.new(@pull, viewer: @owner)

    protected_branch.update!(strict_required_status_checks_policy: true)
    assert_equal :blocked, state.status

    protected_branch.update!(strict_required_status_checks_policy: false)
    assert_equal :blocked, state.status
  end

  context "#unknown_merge_state?" do
    test "returns true when merge state is unknown for the given viewer" do
      assert @pull.create_merge_commit

      @source.refs[@pull.base_ref].append_commit(commit_hash, @owner) do |files|
        files.add("new-file.txt", "New file")
      end

      @pull.reload
      refute @source.rpc.descendant_of?(@pull.merge_commit_sha, @pull.current_base_sha)

      assert @pull.unknown_merge_state?(viewer: @owner)
    end

    test "returns false when merge state is something other than unknown for the given viewer" do
      protected_branch = @source.protect_branch(@pull.base_ref_name, creator: @source.owner,
        required_status_checks: { contexts: %w[ci/janky], include_admins: true },
        entry_point: :test_case,
      )
      protected_branch.update!(strict_required_status_checks_policy: true)

      refute @pull.unknown_merge_state?(viewer: @owner)
    end
  end

  context "#status is :unknown when PR and merge commit is out of date and not yet regenerated" do
    test "without base branch protected" do
      assert @pull.create_merge_commit

      @source.refs[@pull.base_ref].append_commit(commit_hash, @owner) do |files|
        files.add("new-file.txt", "New file")
      end

      @pull.reload
      refute @source.rpc.descendant_of?(@pull.merge_commit_sha, @pull.current_base_sha)

      state = PullRequest::MergeState.new(@pull, viewer: @owner)

      assert_equal :unknown, state.status
    end

    test "with base branch protected" do
      assert @pull.create_merge_commit

      @source.refs[@pull.base_ref].append_commit(commit_hash, @owner) do |files|
        files.add("new-file.txt", "New file")
      end

      protected_branch = @source.protect_branch(@pull.base_ref_name,
        creator: @owner,
        required_status_checks: { contexts: %w[ci/janky], include_admins: true },
        entry_point: :test_case)

      create :status, repository: @source, creator: @owner, sha: @source.refs[@pull.head_ref].target_oid, context: "ci/janky", state: "success"

      @pull.reload
      refute @source.rpc.descendant_of?(@pull.merge_commit_sha, @pull.current_base_sha)

      state = PullRequest::MergeState.new(@pull, viewer: @owner)

      assert_equal :unknown, state.status
    end
  end

  test "#status is :unknown for corrupt pulls (ie a commit is missing)" do
    create(:protected_branch,
      name: @pull.base_ref_name,
      repository: @source,
      creator: @source.owner,
      linear_history_requirement_enforcement_level: :everyone,
    )

    @pull.reload
    @pull.mergeable = true

    @pull.repository.rpc.expects(:descendant_of).once.raises(GitRPC::ObjectMissing.new(nil, ""))

    state = PullRequest::MergeState.new(@pull, viewer: @pull.user)
    assert_equal :unknown, state.status
    assert state.unknown?
    refute state.clean?
    refute state.unstable?
    refute state.dirty?
  end

  context "when required status checks are unsatisfied and pull is behind" do
    test "#status is :behind with strict required status checks policy" do
      @source.refs["master"].append_commit(commit_hash, @owner) do |files|
        files.add("new-file.txt", "New file")
      end

      @pull.reload
      protected_branch = @source.protect_branch(@pull.base_ref_name,
        creator: @source.owner,
        required_status_checks: { contexts: %w[ci/janky], include_admins: true },
        entry_point: :test_case)
      protected_branch.update!(strict_required_status_checks_policy: true)

      assert @pull.create_merge_commit
      assert @pull.behind_base?

      state = PullRequest::MergeState.new(@pull, viewer: @owner)

      assert_equal :behind, state.status
    end

    test "#status is :blocked with loose required status checks policy" do
      @source.refs["master"].append_commit(commit_hash, @owner) do |files|
        files.add("new-file.txt", "New file")
      end

      @pull.reload
      protected_branch = @source.protect_branch(@pull.base_ref_name,
        creator: @source.owner,
        required_status_checks: { contexts: %w[ci/janky], include_admins: true },
        entry_point: :test_case)
      protected_branch.update!(strict_required_status_checks_policy: false)

      assert @pull.create_merge_commit
      assert @pull.behind_base?

      state = PullRequest::MergeState.new(@pull, viewer: @owner)

      assert_equal :blocked, state.status
    end
  end


  test "#status is :blocked when viewer has unresolved review threads and requires linear history" do
    pull = PullRequest.create_for!(@source,
      title: "Sample pull request",
      base: "master",
      head: "update-file-1",
      user: @owner)

    create(:protected_branch,
      name: pull.base_ref_name,
      repository: @source,
      creator: @source.owner,
      required_review_thread_resolution_enforcement_level: :everyone,
      linear_history_requirement_enforcement_level: :everyone,
    )
    assert pull.create_merge_commit

    review = pull.pending_review_for(user: @source.owner)
    thread = review.build_thread
    comment = thread.build_first_comment(
      body: "comment",
      path: "file1",
      start_line: 2,
      line: 3,
    )
    thread.save!
    review.comment!

    state = PullRequest::MergeState.new(pull, viewer: @owner)
    assert_equal :blocked, state.status
  end

  test "#status is :blocked when viewer is not authorized to merge" do
    user = create(:user, login: "nobody")
    admin = create(:user, login: "the-admin")

    org = create(:organization, admin: admin)
    org_repo = create(:repository, owner: org, from_example: :pull_request_fork)
    org_repo.add_member(user, action: :write)

    fork = create(:fork_repository, forker: user, fork_repo: org_repo, from_example: :pull_request_fork)

    pull = PullRequest.create_for!(
      org_repo,
      title: "PR title",
      body: "PR body",
      user: admin,
      base: "#{org_repo.owner}:master",
      head: "#{user}:ahead",
    )

    org_protected_branch = org_repo.protect_branch(pull.base_ref_name, creator: admin, required_status_checks: { include_admins: true }, entry_point: :test_case)
    org_protected_branch.replace_authorized_actors(user_ids: [admin.id], team_ids: [], entry_point: :test_case)

    # pull is not behind

    assert pull.create_merge_commit

    state = PullRequest::MergeState.new(pull, viewer: user)

    assert_predicate state, :blocked_by_unauthorized_protection?

    org_protected_branch.update!(strict_required_status_checks_policy: true)
    assert_equal :blocked, state.status

    org_protected_branch.update!(strict_required_status_checks_policy: false)
    assert_equal :blocked, state.status

    # pull is behind

    org_repo.refs["master"].append_commit({
          message: "Commit on master",
          committer: admin },
        admin) do |files|
      files.add("new-file.txt", "New file")
    end

    assert pull.create_merge_commit
    assert pull.behind_base?

    state = PullRequest::MergeState.new(pull, viewer: user)

    org_protected_branch.update!(strict_required_status_checks_policy: true)
    assert_equal :blocked, state.status

    org_protected_branch.update!(strict_required_status_checks_policy: false)
    assert_equal :blocked, state.status
  end

  context "pull request reviews" do
    test "does not require reviews when feature is disabled" do
      @pull.reload
      protected_branch = @source.protect_branch(@pull.base_ref_name, creator: @source.owner, entry_point: :test_case)

      assert @pull.create_merge_commit

      state = PullRequest::MergeState.new(@pull, viewer: @owner)

      refute_predicate state, :blocked_by_review_policy?
      assert_equal :clean, state.status
    end

    test "requires reviews when feature is enabled" do
      @pull.reload
      protected_branch = @source.protect_branch(@pull.base_ref_name, creator: @source.owner,
        enforce_admins: true, required_pull_request_reviews: { required_approving_review_count: 1 },
        entry_point: :test_case)

      assert @pull.create_merge_commit

      state = PullRequest::MergeState.new(@pull, viewer: @owner)

      assert_predicate state, :blocked_by_review_policy?
      assert_equal :blocked, state.status
    end
  end

  if GitHub.merge_queues_enabled?
    context "merge queue" do
      test "status is :clean when merge queue is enabled and PR is not in the queue" do
        enable_feature_flag(:merge_queue, @pull.repository)

        protected_branch = create(:protected_branch,
          name: @pull.base_ref_name,
          repository: @source,
          creator: @source.owner,
        )
        protected_branch.enable_merge_queue
        protected_branch.save!

        assert @pull.create_merge_commit

        state = PullRequest::MergeState.new(@pull, viewer: @owner)

        assert state.clean?
        refute state.unknown?
        refute state.unstable?
        refute state.dirty?
      end

      test "status is :clean when merge queue is enabled and PR is in the queue" do
        enable_feature_flag(:merge_queue, @pull.repository)

        protected_branch = create(:protected_branch,
          name: @pull.base_ref_name,
          repository: @source,
          creator: @source.owner,
        )
        protected_branch.enable_merge_queue
        protected_branch.save!

        assert @pull.create_merge_commit
        protected_branch.merge_queue.enqueue!(
          pull_request: @pull,
          enqueuer: @source.owner,
        )
        assert protected_branch.merge_queue.entry_for(pull_request: @pull)

        state = PullRequest::MergeState.new(@pull, viewer: @owner)

        assert state.clean?
        refute state.unknown?
        refute state.unstable?
        refute state.dirty?
      end

      test "status is :clean when merge queue, required deployements, and deploy-then-merge is enabled" do
        enable_feature_flag(:merge_queue, @pull.repository)
        enable_feature_flag(:merge_queue_deploy_then_merge, @pull.repository)

        protected_branch = create(:protected_branch,
          name: @pull.base_ref_name,
          repository: @source,
          creator: @source.owner,
        )
        protected_branch.enable_merge_queue
        protected_branch.replace_required_deployment_environments("production")
        protected_branch.enable_required_deployments
        protected_branch.save!

        assert @pull.create_merge_commit

        state = PullRequest::MergeState.new(@pull, viewer: @owner)

        assert state.clean?
        refute state.unknown?
        refute state.unstable?
        refute state.dirty?
        refute state.blocked_by_required_deployments?
      end

      test "is blocked_by_review_policy if the pull_request has not been queued" do
        enable_feature_flag(:merge_queue, @pull.repository)

        protected_branch = @source.protect_branch(
          @pull.base_ref_name,
          creator: @source.owner,
          required_status_checks: { contexts: %w[required-run other-required-run] },
          entry_point: :test_case,
        )
        protected_branch.enable_required_pull_request_reviews
        protected_branch.enable_merge_queue
        protected_branch.save!

        state = PullRequest::MergeState.new(@pull, viewer: @owner)
        assert state.blocked_by_review_policy?
      end

      test "is not blocked_by_review_policy if the pull_request has already been queued" do
        enable_feature_flag(:merge_queue, @pull.repository)

        protected_branch = @source.protect_branch(
          @pull.base_ref_name,
          creator: @source.owner,
          required_status_checks: { contexts: %w[required-run] },
          entry_point: :test_case,
        )
        protected_branch.enable_merge_queue
        protected_branch.save!

        assert @pull.create_merge_commit
        create(:check_suite, :success, repository: @source, head_sha: @pull.merge_commit_sha, display_name: "required-run")

        protected_branch.merge_queue.enqueue!(
          pull_request: @pull,
          enqueuer: @source.owner,
        )

        assert @pull, :in_merge_queue?

        protected_branch.enable_required_pull_request_reviews

        state = PullRequest::MergeState.new(@pull, viewer: @owner)

        refute state.blocked_by_review_policy?
      end
    end
  end

  context "can_update_ref?" do
    test "is false when merge_commit_sha is nil" do
      @pull.merge_commit_sha = nil
      merge_state = @pull.merge_state(viewer: @pull.user)
      refute_predicate merge_state, :can_update_ref?
    end

    test "is false when current_base_sha is nil (i.e base branch has been deleted)" do
      @pull.expects(:current_base_sha).returns(nil).at_least_once
      merge_state = @pull.merge_state(viewer: @pull.user)
      refute_predicate merge_state, :can_update_ref?
    end

    context "with loose required status policy" do
      test "is true when base branch has failure status and head is behind base" do
        # base branch starts green
        master = @source.refs.find("master")
        create :status, repository: @source, creator: @source.owner, sha: master.sha, context: "foo", state: "success"

        # head branch starts green with one commit ahead of base
        topic = @source.refs.create("refs/heads/topic", master.target_oid, @source.owner)
        topic.append_commit(commit_hash(message: "Commit on topic"), @owner) do |files|
          files.add("some-new-file.txt", "New file")
        end
        create :status, repository: @source, creator: @source.owner, sha: topic.sha, context: "foo", state: "success"

        # creating the PR makes sure that #base_sha points to where head branch branched off of base
        issue = create(:issue, user: @source.owner, repository: @source, body: "whatever")
        pull = PullRequest.create_for!(@source,
          title: "a pull request",
          base: "master",
          head: topic.ref,
          user: @owner,
          issue: issue)

        # adding a commit to base to make the PR out-of-date and make base branch red
        master.append_commit(commit_hash, @owner) do |files|
          files.add("another-new-file.txt", "New file")
        end
        create :status, repository: @source, creator: @source.owner, sha: master.sha, context: "foo", state: "failure"

        # protecting base branch with loose policy
        @protected_branch = create(:protected_branch, repository: @source, creator: @source.owner, required_status_checks_enforcement_level: :everyone, strict_required_status_checks_policy: false)
        @protected_branch.replace_status_contexts(%w[foo])

        assert pull.create_merge_commit, "creating merge commit failed"

        merge_state = pull.merge_state(viewer: @source.owner)
        assert merge_state.rules_engine_evaluation_result.rules_fulfilled?, "protected branch policy unfulfilled"
        assert merge_state.can_update_ref?, "cannot update ref"
      end

      test "is true when base branch has failure status and head is up-to-date" do
        # base branch starts red
        master = @source.refs.find("master")
        create :status, repository: @source, creator: @source.owner, sha: master.sha, context: "foo", state: "failure"

        # head branch starts green with one commit ahead of base
        topic = @source.refs.create("refs/heads/topic", master.target_oid, @source.owner)
        topic.append_commit(commit_hash(message: "Commit on topic"), @owner) do |files|
          files.add("some-new-file.txt", "New file")
        end
        create :status, repository: @source, creator: @source.owner, sha: topic.sha, context: "foo", state: "success"

        # creating the PR makes sure that #base_sha points to where head branch branched off of base
        issue = create(:issue, user: @source.owner, repository: @source, body: "whatever")
        pull = PullRequest.create_for!(@source,
          title: "a pull request",
          base: "master",
          head: topic.ref,
          user: @owner,
          issue: issue)

        # protecting base branch with loose policy
        @protected_branch = create(:protected_branch, repository: @source, creator: @source.owner, required_status_checks_enforcement_level: :everyone, strict_required_status_checks_policy: false)
        @protected_branch.replace_status_contexts(%w[foo])

        assert_predicate pull, :create_merge_commit
        merge_state = pull.merge_state(viewer: @source.owner)

        assert merge_state.rules_engine_evaluation_result.rules_fulfilled?, "protected branch policy unfulfilled"
        assert merge_state.can_update_ref?, "cannot update ref"
      end
    end
  end

  context "#rules_engine_evaluation_result" do
    test "denies when merge_commit_sha is nil" do
      @pull.merge_commit_sha = nil
      merge_state = @pull.merge_state(viewer: @pull.user)
      refute merge_state.rules_engine_evaluation_result.rules_fulfilled?
    end

    test "denies when current_base_sha is nil (i.e base branch has been deleted)" do
      @pull.expects(:current_base_sha).returns(nil).at_least_once
      merge_state = @pull.merge_state(viewer: @pull.user)
      refute merge_state.rules_engine_evaluation_result.rules_fulfilled?
    end
  end
end
