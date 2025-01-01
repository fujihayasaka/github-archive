# typed: true
# frozen_string_literal: true

require "test_helper"

class ProtectedBranchPolicyTest < GitHub::TestCase
  include GpgKeyHelper
  include GitHub::LoggerHelper
  include RepositoriesTestHelper
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    Spokesd.enable_spokesd

    @gpg_key = create_gpg_key
    @user = @gpg_key.user

    @repo = create(:repository, from_example: :simple)
    @repo.add_member @user, action: :write
    @protected_branch = create(:protected_branch,
      repository: @repo,
      creator: @user,
      required_status_checks_enforcement_level: :non_admins,
      pull_request_reviews_enforcement_level: :off)

    @reviewer = create(:user, login: "reviewer")
    @review_repo = create :private_repository, name: "review_repo", from_example: :simple
    @review_repo.add_member @reviewer, action: :write
    @review_repo.add_member @user, action: :write
    @review_protected_branch = create(:protected_branch,
      repository: @review_repo,
      creator: @user,
      required_status_checks_enforcement_level: :off,
      pull_request_reviews_enforcement_level: :everyone)
    @pull = PullRequest.create_for!(@review_repo,
      base: "master",
      head: "cr-line-endings",
      user: @user,
      title: "convert to CR line ending",
      body: "most valuable PR ever A++++ please do merge",
    )

    @org = create(:business_plus_organization)
    @org_admin = @org.admins.first
    @org_repo = create(:repository, owner: @org, from_example: :simple)
    @org_protected_branch = create(:protected_branch, repository: @org_repo, creator: @user, required_status_checks_enforcement_level: :non_admins)

    @signature_required_repo = create(:repository, from_example: :signed_commits)
    @signature_required_repo.add_member @user, action: :write
    @signature_required_branch = create(:protected_branch,
      repository: @signature_required_repo,
      creator: @user,
      required_status_checks_enforcement_level: :off,
      pull_request_reviews_enforcement_level: :off,
      signature_requirement_enforcement_level: :non_admins,
    )
    @unsigned_commit = {
      before: "378718a43decc3471c6a90b8aac95440a4e11152",
      after:  "d014786a170b6ef6ed6a1814be8c941db39cd259",
    }

    @signed_commit = {
      before: "42fc37b8c953056c2dfa5d489b0209bd66f53481",
      after: "0f4ae7f6122a5759211677dc8295211eaadb36c7",
    }

    @invalid_signed_commit = {
      before: "0f4ae7f6122a5759211677dc8295211eaadb36c7",
      after: "ec57bd7828c8e9a0ac246e2a7166fe3e9a4ceab3",
    }

    @signed_and_unsigned_commits = {
      before: GitHub::NULL_OID,
      after: "d014786a170b6ef6ed6a1814be8c941db39cd259",
    }

    @blocked_merge_commit_repo = create(:repository, owner: @user, from_example: :merges)
    @blocked_merge_commit_branch = create(:protected_branch,
      repository: @blocked_merge_commit_repo,
      creator: @user,
      linear_history_requirement_enforcement_level: :everyone,
    )

    @merge_update = {
      before: "306dc50d0050d03723336d021256a25c633c98b1",
      after: "61239bf2e4b76585769854d1344e0adcff0dcd00",
    }

    @linear_update = {
      before: "6474d6f3f73a3754e9562f0075d70e73cf1338c0",
      after: "774765d9f11b1661071207fdc62004d34facfc23",
    }

    @github_app = create :integration, default_permissions: { "checks" => :write }
    @installation = make_integration_installation integration: @github_app, repository: @repo

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    @protected_branch.enable_blocked_deletions
    @review_protected_branch.enable_blocked_deletions
    @org_protected_branch.enable_blocked_deletions
    @signature_required_branch.enable_blocked_deletions
    @blocked_merge_commit_branch.enable_blocked_deletions
  end

  test "allows deleting tags" do
    tag = @repo.tags.create("foo", "63611721afd41f58f801d66e543d8288b4c5eb44", @user)

    ref_update = create_tag_update(@repo, name: tag.name,
                                      before_oid: tag.target_oid, after_oid: GitHub::NULL_OID)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert decision.rules_fulfilled?, "check failed: #{decision}"
    assert_nil decision.message
  end

  test "allows deleting other non-branch refs" do
    ref = @repo.refs.create("refs/not-heads/foo", "63611721afd41f58f801d66e543d8288b4c5eb44", @user)

    ref_update = create_ref_update(@repo, name: ref.qualified_name,
                                      before_oid: ref.target_oid, after_oid: GitHub::NULL_OID)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert decision.rules_fulfilled?, "check failed: #{decision}"
    assert_nil decision.message
  end

  test "allows deleting unprotected branches" do
    oid = @repo.heads["cr-line-endings"].target_oid

    ref_update = create_branch_update(@repo, name: "cr-line-endings",
                                      before_oid: oid, after_oid: GitHub::NULL_OID)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert decision.rules_fulfilled?, "check failed: #{decision}"
    assert_nil decision.message
  end

  context "for required deployments" do
    test "passes when the branch has required deployments enabled" do
      @protected_branch.enable_required_deployments
      @protected_branch.save!

      required_deployment_1 = @protected_branch.required_deployments.create!(environment: "production")
      required_deployment_2 = @protected_branch.required_deployments.create!(environment: "staging")

      master_oid = @repo.heads["master"].target_oid
      topic = @repo.heads.create("new-topic", master_oid, @user)
      topic.append_commit({ message: "commit 1", committer: @user }, @user) do |files|
        files.add "some_file", "some content"
      end

      ref_update = create_branch_update(
        @repo,
        name: "master",
        before_oid: master_oid,
        after_oid: topic.target_oid,
      )

      # Should be denied when there haven't been any deployments
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)
      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      run = decision.runs_by_rule_type(:required_deployments).find(&:failed?)
      assert run.present?

      # Should be denied when the deployment has no statuses
      deployment_1 = @repo.deployments.create!(environment: "production", creator: @user, sha: topic.target_oid)
      deployment_2 = @repo.deployments.create!(environment: "staging", creator: @user, sha: topic.target_oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)
      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      run = decision.runs_by_rule_type(:required_deployments).find(&:failed?)
      assert run.present?
      assert_equal "Missing successful active production and staging deployments.", run&.message

      # Satisfy staging deployment requirement
      deployment_2.statuses.create!(creator: @user, state: "success")

      # Should be denied when latest status isn't succcessful
      status = deployment_1.statuses.create!(creator: @user, state: "pending")
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)
      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      run = decision.runs_by_rule_type(:required_deployments).find(&:failed?)
      assert run.present?
      assert_equal "Missing successful active production deployment.", run&.message

      # Should be allowed when latest status is succcessful
      status = deployment_1.statuses.create!(creator: @user, state: "success")
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)
      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "admin override" do
      master_oid = @repo.heads["master"].target_oid
      topic = @repo.heads.create("new-topic", master_oid, @user)
      topic.append_commit({ message: "commit 1", committer: @user }, @user) do |files|
        files.add "some_file", "some content"
      end

      required_deployment = @protected_branch.required_deployments.create!(environment: "production")

      ref_update = create_branch_update(
        @repo,
        name: "master",
        before_oid: master_oid,
        after_oid: topic.target_oid,
      )

      @protected_branch.enable_required_deployments
      @protected_branch.admin_enforced = false
      @protected_branch.save!

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)
      refute_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?

      @protected_branch.admin_enforced = true
      @protected_branch.save!

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)
      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
    end

    test "succeeds for updates with same trees but different commits" do
      required_deployment = @protected_branch.required_deployments.create!(environment: "production")

      @protected_branch.enable_required_deployments
      @protected_branch.admin_enforced = false
      @protected_branch.save!

      branch_one = @repo.refs.find("cr-line-endings")
      branch_two = @repo.refs.create("refs/heads/cr-line-endings-two", branch_one.target_oid, @user)
      branch_two.append_commit({ message: "Empty commit", committer: @user }, @user)

      assert_equal branch_one.target.tree_oid, branch_two.target.tree_oid # sanity check

      deployment = @repo.deployments.create!(environment: "production", creator: @user, sha: branch_one.target_oid)
      status = deployment.statuses.create!(creator: @user, state: "success")

      merge_commit = @repo.commits.create_merge_commit(@user, "master", branch_one.name).first
      ref_update = create_branch_update(@repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

      assert decision.rules_fulfilled?, "check failed: #{decision} - #{decision.failed_rule_types}"
      assert_nil decision.message
    end
  end

  context "for required review thread resolution" do
    test "passes with feature flag enabled and all comments are resolved with a merge commit" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      user = create(:user)
      @review_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: user)
      create(:pull_request_review, :commented, pull_request: @pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!
      comment.pull_request_review_thread.resolve(resolver: @user)

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @review_repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      assert_predicate decision, :rules_fulfilled?
    end

    test "passes with pull request from a forked repo with all threads resolved" do
      org = create :organization, plan: GitHub::Plan.business, login: "an-org", admin: @user
      org.add_admin(@user)
      org_repo = create(:repository, owner: org, from_example: :pull_request_source)

      org_repo_protected_branch = create(:protected_branch,
        repository: org_repo,
        creator: @user,
        name: "master")
      org_repo_protected_branch.enable_required_review_thread_resolution
      org_repo_protected_branch.save!

      forker = create(:user)
      fast_fork_repo(org_repo, example: :pull_request_fork, owner: forker)

      fork_pull = PullRequest.create_for!(org_repo,
        user: forker,
        base: "#{org}:master",
        head: "#{forker}:topic",
        title: "testing pull request",
        body: "just some thing",
      )

      user = create(:user)
      org_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: fork_pull, user: user)
      create(:pull_request_review, :commented, pull_request: fork_pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!
      comment.pull_request_review_thread.resolve(resolver: @user)

      merge_commit = fork_pull.create_merge_commit
      ref_update = create_branch_update(org_repo,
        name: "master",
        before_oid: org_repo.heads["master"].target_oid,
        after_oid: merge_commit)

      decision = RuleEngine::Evaluator.evaluate_rules_one(org_repo, ref_update, @user)
      assert decision, :rules_fulfilled?
    end

    test "fails with pull request from a forked repo with an unresolved thread" do
      org = create :organization, plan: GitHub::Plan.business, login: "an-org", admin: @user
      org.add_admin(@user)
      org_repo = create(:repository, owner: org, from_example: :pull_request_source)

      org_repo_protected_branch = create(:protected_branch,
        repository: org_repo,
        creator: @user,
        name: "master")
      org_repo_protected_branch.enable_required_review_thread_resolution
      org_repo_protected_branch.save!

      forker = create(:user)
      fast_fork_repo(org_repo, example: :pull_request_fork, owner: forker)

      fork_pull = PullRequest.create_for!(org_repo,
        user: forker,
        base: "#{org}:master",
        head: "#{forker}:topic",
        title: "testing pull request",
        body: "just some thing",
      )

      user = create(:user)
      org_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: fork_pull, user: user)
      create(:pull_request_review, :commented, pull_request: fork_pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!

      merge_commit = fork_pull.create_merge_commit
      ref_update = create_branch_update(org_repo,
        name: "master",
        before_oid: org_repo.heads["master"].target_oid,
        after_oid: merge_commit)

      decision = RuleEngine::Evaluator.evaluate_rules_one(org_repo, ref_update, @user)
      refute_predicate decision, :rules_fulfilled?
      run = decision.runs_by_rule_type(:required_review_thread_resolution).find(&:failed?)
      assert run.present?
    end

    test "fails with feature flag enabled and unresolved comments with a merge commit" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save

      user = create(:user)
      @review_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: user)
      create(:pull_request_review, :commented, pull_request: @pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @review_repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      refute_predicate decision, :rules_fulfilled?
      run = decision.runs_by_rule_type(:required_review_thread_resolution).find(&:failed?)
      assert run.present?
    end

    test "passes with feature flag enabled and no review comments with a merge commit" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @review_repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      assert_predicate decision, :rules_fulfilled?
    end

    test "fails with feature flag disabled" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @review_repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      assert_predicate decision, :rules_fulfilled?
    end

    test "passes with feature flag enabled and all comments are resolved" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      user = create(:user)
      @review_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: user)
      create(:pull_request_review, :commented, pull_request: @pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!
      comment.pull_request_review_thread.resolve(resolver: @user)

      master_oid = @review_repo.heads["master"].target_oid
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: @pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      assert_predicate decision, :rules_fulfilled?
    end

    test "fails with feature flag enabled and unresolved comments" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      user = create(:user)
      @review_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: user)
      create(:pull_request_review, :commented, pull_request: @pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!

      master_oid = @review_repo.heads["master"].target_oid
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: @pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      refute_predicate decision, :rules_fulfilled?
      run = decision.runs_by_rule_type(:required_review_thread_resolution).find(&:failed?)
      assert run.present?
    end

    test "works correctly when squash-merging PR" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      user = create(:user)
      @review_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: user)
      create(:pull_request_review, :commented, pull_request: @pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!

      # Generate a merge commit. We won't use this system commit, but we'll use the tree.
      @pull.create_merge_commit
      merge_ref = @review_repo.refs.read(@pull.merge_ref)
      system_merge_commit = merge_ref.target

      master_oid = @review_repo.heads["master"].target_oid

      # Create a squash commit.
      squash_metadata = { message: "squash", committer: @user, tree: system_merge_commit.tree_oid }
      squash_commit = @review_repo.commits.create(squash_metadata, master_oid)

      # Pull request merge uses Branch::Update rather than Ref::Update. This lets us determine a specific pull request.
      ref_update = Git::Branch::Update.new(repository: @review_repo, refname: "refs/heads/master",
        before_oid: master_oid, after_oid: squash_commit.oid,
        pull_request: @pull)

      # Policy should block, because comment on @pull is unresolved
      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      refute_predicate decision, :rules_fulfilled?
      run = decision.runs_by_rule_type(:required_review_thread_resolution).find(&:failed?)
      assert run.present?

      comment.pull_request_review_thread.resolve(resolver: @user)

      # Policy should be fulfilled, because comment on @pull is resolved
      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      assert_predicate decision, :rules_fulfilled?
      run = decision.runs_by_rule_type(:required_review_thread_resolution).find(&:failed?)
      refute run.present?
    end

    test "passes with feature flag enabled and no review comments" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      assert_empty @pull.review_threads, "setup is wrong, pull request should have any reviews"

      master_oid = @review_repo.heads["master"].target_oid
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: @pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      assert_predicate decision, :rules_fulfilled?
    end

    test "works when feature flag enabled, all comments are resolved, base branch of PR is not the default branch, and the commit is already in default" do
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      @review_repo.heads["master"].append_commit({ message: "Add README", committer: @review_repo.owner }, @review_repo.owner) do |files|
        files.add("README.md", "#bluewind\n \xB2\xE2\xCA\xD4\xCC\xE1\xBD\xBB\n".b)
      end

      protected_branch = create(:protected_branch,
        repository: @review_repo,
        creator: @user,
        name: "cr-line-endings",
        required_status_checks_enforcement_level: :off,
        block_force_pushes_enforcement_level: :off)

      protected_branch.enable_required_review_thread_resolution
      protected_branch.save!

      pull = PullRequest.create_for!(@review_repo,
        base: "cr-line-endings",
        head: "master",
        user: @user,
        title: "convert to CR line ending",
        body: "most valuable PR ever A++++ please do merge",
      )

      user = create(:user)
      @review_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: pull, user: user)
      create(:pull_request_review, :commented, pull_request: @pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!
      comment.pull_request_review_thread.resolve(resolver: @user)

      base_oid = @review_repo.heads["cr-line-endings"].target_oid
      ref_update = create_branch_update(@review_repo,
        name: "cr-line-endings",
        before_oid: base_oid,
        after_oid: pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      assert_predicate decision, :rules_fulfilled?
    end

    test "fails when feature flag enabled, there are unresolved comments, base branch of PR is not the default branch, and the commit is already in default" do
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      @review_repo.heads["master"].append_commit({ message: "Add README", committer: @review_repo.owner }, @review_repo.owner) do |files|
        files.add("README.md", "#bluewind\n \xB2\xE2\xCA\xD4\xCC\xE1\xBD\xBB\n".b)
      end

      protected_branch = create(:protected_branch,
        repository: @review_repo,
        creator: @user,
        name: "cr-line-endings",
        required_status_checks_enforcement_level: :off,
        block_force_pushes_enforcement_level: :off)

      protected_branch.enable_required_review_thread_resolution
      protected_branch.save!

      pull = PullRequest.create_for!(@review_repo,
        base: "cr-line-endings",
        head: "master",
        user: @user,
        title: "convert to CR line ending",
        body: "most valuable PR ever A++++ please do merge",
      )

      user = create(:user)
      @review_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: pull, user: user)
      create(:pull_request_review, :commented, pull_request: @pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!

      base_oid = @review_repo.heads["cr-line-endings"].target_oid
      ref_update = create_branch_update(@review_repo,
        name: "cr-line-endings",
        before_oid: base_oid,
        after_oid: pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      refute_predicate decision, :rules_fulfilled?
    end

    test "admin override" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      user = create(:user)
      @review_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: user)
      create(:pull_request_review, :commented, pull_request: @pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!

      master_oid = @review_repo.heads["master"].target_oid
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: @pull.head_sha,
      )

      @review_protected_branch.admin_enforced = false
      @review_protected_branch.save!

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      refute_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?

      @review_protected_branch.admin_enforced = true
      @review_protected_branch.save!

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
    end

    test "passes with feature flag enabled and pending unresolved review" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      user = create(:user)
      @review_repo.add_member(user, action: :write)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: user)
      create(:pull_request_review, :commented, pull_request: @pull, user: user, review_comments: [comment], review_threads: [comment.pull_request_review_thread], state: :pending)
      comment.submit!

      master_oid = @review_repo.heads["master"].target_oid
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: @pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      assert_predicate decision, :rules_fulfilled
    end

    test "passes with unresolved, non replied code scanning comments" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      user = create(:user)
      review = @pull.build_code_scanning_variant_review do |r|
        r.user = user
      end

      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "a",
        line: 1,
      ).save!
      review.comment!

      master_oid = @review_repo.heads["master"].target_oid
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: @pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      assert_predicate decision, :rules_fulfilled?
    end

    test "fails with unresolved, replied code scanning comments" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      user = create(:user)
      review = @pull.build_code_scanning_variant_review do |r|
        r.user = user
      end

      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "a",
        line: 1,
      ).save!
      review.comment!

      thread.build_reply(
        user: user,
        body: "ok",
      ).save!

      master_oid = @review_repo.heads["master"].target_oid
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: @pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      refute_predicate decision, :rules_fulfilled?
      run = decision.runs_by_rule_type(:required_review_thread_resolution).find(&:failed?)
      assert run.present?
    end

    test "passes with resolved, replied code scanning comments" do
      @review_protected_branch.enable_required_review_thread_resolution
      @review_protected_branch.clear_required_pull_request_reviews
      @review_protected_branch.save!

      user = create(:user)
      review = @pull.build_code_scanning_variant_review do |r|
        r.user = user
      end

      thread = review.build_thread
      comment = thread.build_first_comment(
        body: "comment",
        path: "a",
        line: 1,
      ).save!
      review.comment!

      thread.build_reply(
        user: user,
        body: "ok",
      ).save!

      thread.resolve(resolver: user)

      master_oid = @review_repo.heads["master"].target_oid
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: @pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      assert_predicate decision, :rules_fulfilled
    end
  end

  context "for pull request reviews" do
    test "denies when there are no reviews" do
      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:pull_request).find(&:failed?)
      assert run.present?
      assert_equal "At least 1 approving review is required by reviewers with write access.", run&.message
    end

    test "denies when there are rejected reviews" do
      review = create(:pull_request_review, pull_request: @pull, user: @reviewer, body: "this is bad")
      review.request_changes!

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:pull_request).find(&:failed?)
      assert run.present?
      assert_equal "1 review requesting changes by reviewers with write access.", run&.message
    end

    test "passes when there is at least one approved review" do
      review = create(:pull_request_review, pull_request: @pull, user: @reviewer)
      review.approve!

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "passes when a fast-forward merge with approval is pushed" do
      #        before (PR base)
      #      ↙
      # o---A---o---o---B
      #                   ↖
      #                     after (PR head)
      #
      # Pushing commit B

      master_oid = @review_repo.heads["master"].target_oid
      topic = @review_repo.heads.create("new-topic", master_oid, @user)
      topic.append_commit({ message: "commit 1", committer: @user }, @user) do |files|
        files.add "some_file", "some content"
      end
      topic.append_commit({ message: "commit 2", committer: @user }, @user) do |files|
        files.add "another_file", "more content"
      end

      pull = PullRequest.create_for!(@review_repo,
        base: "master",
        head: "new-topic",
        user: @user,
        title: "New Topic",
        body: "New Topic",
      )

      review = pull.reviews.create(head_sha: pull.head_sha, user: @reviewer)
      review.approve!

      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "passes when a single merge commit with approval is pushed (direct merge)" do
      # o---o---M <- master
      #      \ /
      #       A   <- PR with approving review
      #
      # Pushing commit M

      master_oid = @review_repo.heads["master"].target_oid
      ref = @review_repo.heads.create("new-topic", master_oid, @user)
      commit = ref.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "some_file", "some content"
      end

      pull = PullRequest.create_for!(@review_repo,
        base: "master",
        head: "new-topic",
        user: @user,
        title: "New Topic",
        body: "New Topic",
      )
      merge_commit = @review_repo.commits.create_merge_commit(@user, master_oid, commit.oid).first

      review = pull.reviews.create(head_sha: "xxxxx", user: @reviewer)
      review.approve!

      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: merge_commit.oid,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "passes when a single merge commit with approval is pushed (normal merge)" do
      # o---o---o---M <- master
      #      \     /
      #       A---B   <- PR with approving review
      #
      # Pushing commit M

      master_parent_oid = @review_repo.heads["master"].target.first_parent_oid
      master_oid = @review_repo.heads["master"].target_oid

      ref = @review_repo.heads.create("new-topic", master_parent_oid, @user)
      commit1 = ref.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "some_file", "some content"
      end
      commit2 = ref.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "another_file", "more content"
      end

      pull = PullRequest.create_for!(@review_repo,
        base: "master",
        head: "new-topic",
        user: @user,
        title: "New Topic",
        body: "New Topic",
      )
      merge_commit = @review_repo.commits.create_merge_commit(@user, master_oid, commit2.oid).first

      review = pull.reviews.create(head_sha: "xxxxx", user: @reviewer)
      review.approve!

      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: merge_commit.oid,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "passes when fast-forward merge of a merge commit with approval is pushed" do
      #            before
      #          ↙
      # o---o---o
      #          \
      #           o---M  ← after
      #            \ /
      #             o
      #
      # Pushing commit M

      master_oid = @review_repo.heads["master"].target_oid

      topic = @review_repo.heads.create("new-topic", master_oid, @user)
      topic.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "some_file", "some content"
      end
      sub_topic = @review_repo.heads.create("sub-topic", topic.target_oid, @user)
      sub_topic.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "another_file", "more content"
      end
      merge_commit = @review_repo.commits.create_merge_commit(@user, topic.target_oid, sub_topic.target_oid).first
      topic.update(merge_commit, @user)

      pull = PullRequest.create_for!(@review_repo,
        base: "master",
        head: "new-topic",
        user: @user,
        title: "New Topic",
        body: "New Topic",
      )

      review = pull.reviews.create(head_sha: pull.head_sha, user: @reviewer)
      review.approve!

      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: pull.head_sha,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "denies when merge of a merge commit with approval is pushed" do
      #            before
      #          ↙
      # o---o---o-------M2 ← after
      #          \     /
      #           o---M1
      #            \ /
      #             o
      #
      # Pushing commit M2

      master_oid = @review_repo.heads["master"].target_oid

      topic = @review_repo.heads.create("new-topic", master_oid, @user)
      topic.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "some_file", "some content"
      end
      sub_topic = @review_repo.heads.create("sub-topic", topic.target_oid, @user)
      sub_topic.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "another_file", "more content"
      end
      merge_commit_1 = @review_repo.commits.create_merge_commit(@user, topic.target_oid, sub_topic.target_oid).first
      merge_commit_2 = @review_repo.commits.create_merge_commit(@user, master_oid, merge_commit_1.oid).first

      pull = PullRequest.create_for!(@review_repo,
        base: "master",
        head: "new-topic",
        user: @user,
        title: "New Topic",
        body: "New Topic",
      )

      review = pull.reviews.create(head_sha: "xxxxx", user: @reviewer)
      review.approve!

      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: merge_commit_2.oid,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:pull_request).find(&:failed?)
      assert run.present?
      assert_equal "Changes must be made through a pull request.", run&.message
    end

    test "denies when several merge commits are pushed (with approval)" do
      # o---o---o---o---M1---M2 <- master
      #      \         /    /
      #       A---B---C    /    <- PR with approving review
      #       ------------D     <- Not part of PR => no approving review
      #
      # Pushing commits M1 and M2

      topic = @review_repo.heads.create("new-topic", @review_repo.heads["master"].target_oid, @user)
      topic.append_commit({ message: "commit 1", committer: @user }, @user) do |files|
        files.add "file_1", "some content"
      end
      commit = topic.append_commit({ message: "commit 2", committer: @user }, @user) do |files|
        files.add "file_2", "some content"
      end

      merge_commit_1 = @review_repo.commits.create_merge_commit(@user, @review_repo.heads["master"].target_oid, commit.oid).first

      other_topic = @review_repo.heads.create("other-topic", @review_repo.heads["master"].target.first_parent_oid, @user)
      commit = other_topic.append_commit({ message: "commit 3", committer: @user }, @user) do |files|
        files.add "file_3", "some content"
      end

      merge_commit_2 = @review_repo.commits.create_merge_commit(@user, merge_commit_1.oid, commit.oid).first

      # approving merge commit 1
      review = @pull.reviews.create(head_sha: "xxxxx", user: @reviewer)
      review.approve!

      pull = PullRequest.create_for!(@review_repo,
        base: "master",
        head: "new-topic",
        user: @user,
        title: "New Topic",
        body: "New Topic",
      )

      # approving merge commit 2
      review = pull.reviews.create(head_sha: "xxxxx", user: @reviewer)
      review.approve!

      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @review_repo.heads["master"].target_oid,
        after_oid: merge_commit_2.oid,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:pull_request).find(&:failed?)
      assert run.present?
      assert_equal "Changes must be made through a pull request.", run&.message
    end

    test "denies when several merge commits are pushed (without approval)" do
      # o---o---o---o---M1---M2 <- master
      #      \         /    /
      #       A---B---C    /    <- PR with approving review
      #       ------------D     <- Not part of PR => no approving review
      #
      # Pushing commits M1 and M2

      merge_commit_1 = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first

      ref = @review_repo.heads.create("new-topic", @review_repo.heads["master"].target.first_parent_oid, @user)
      commit = ref.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "some_file", "some content"
      end

      merge_commit_2 = @review_repo.commits.create_merge_commit(@user, merge_commit_1.oid, commit.oid).first

      review = @pull.reviews.create(head_sha: "xxxxx", user: @reviewer)
      review.approve!

      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @review_repo.heads["master"].target_oid,
        after_oid: merge_commit_2.oid,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:pull_request).find(&:failed?)
      assert run.present?
      assert_equal "Changes must be made through a pull request.", run&.message
    end

    test "denies when merge of two merge commits with approval is pushed" do
      #                    before
      #                  ↙
      # o---o---o---o---o---M1---M3
      #      \             /    /  ↖
      #       o---o---o---*    /     after
      #        \              /
      #         o---o---*---M2
      #          \         /
      #           o---o---*
      #
      # Pushing commits M1 and M3

      master_oid = @review_repo.heads["master"].target_oid

      topic = @review_repo.heads.create("new-topic", master_oid, @user)
      topic.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "some_file", "some content"
      end
      merge_commit_1 = @review_repo.commits.create_merge_commit(@user, master_oid, topic.target_oid).first

      sub_topic = @review_repo.heads.create("sub-topic", topic.target_oid, @user)
      sub_topic.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "another_file", "more content"
      end
      sub_sub_topic = @review_repo.heads.create("sub-sub-topic", sub_topic.target_oid, @user)
      sub_sub_topic.append_commit({ message: "commit", committer: @user }, @user) do |files|
        files.add "again_another_file", "way more content"
      end
      merge_commit_2 = @review_repo.commits.create_merge_commit(@user, sub_topic.target_oid, sub_sub_topic.target_oid).first

      merge_commit_3 = @review_repo.commits.create_merge_commit(@user, merge_commit_1.oid, merge_commit_2.oid).first

      %w[new-topic sub-topic sub-sub-topic].each do |head_branch|
        pull = PullRequest.create_for!(@review_repo,
          base: "master",
          head: head_branch,
          user: @user,
          title: head_branch,
          body: head_branch,
        )

        review = pull.reviews.create(head_sha: "xxxxx", user: @reviewer)
        review.approve!
      end

      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: master_oid,
        after_oid: merge_commit_3.oid,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:pull_request).find(&:failed?)
      assert run.present?
      assert_equal "Changes must be made through a pull request.", run&.message
    end

    test "denies when the pushed commits contain commits not part of any PR" do
      # o---o---o---o---M---D   <- master
      #      \         /
      #       A---B---C         <- PR with approving review
      #
      # Pushing commits M and D

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      commit = @review_repo.commits.create(
        { message: "commit", committer: @user },
        merge_commit.oid) do |files|
        files.add "some_file", "some content"
      end

      review = @pull.reviews.create(head_sha: "xxxxx", user: @reviewer)
      review.approve!

      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @review_repo.heads["master"].target_oid,
        after_oid: commit.oid,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:pull_request).find(&:failed?)
      assert run.present?
      assert_equal "Changes must be made through a pull request.", run&.message
    end

    test "passes when branch is being deleted" do
      @review_protected_branch.clear_blocked_deletions
      @review_protected_branch.save!

      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @review_repo.heads["master"].target_oid,
        after_oid: GitHub::NULL_OID)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)
      assert_predicate decision, :rules_fulfilled?
    end

    test "passes when there is no reviewers but we do not require reviewers" do
      @review_protected_branch.required_approving_review_count = 0
      @review_protected_branch.save!

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "fails when there is 0 required reviewers but we do not use a pull request" do
      @review_protected_branch.required_approving_review_count = 0
      @review_protected_branch.save!

      @pull.destroy

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?

      assert_equal 1, decision.failed_rule_types.size
      run = decision.runs_by_rule_type(:pull_request).find(&:failed?)
      assert run.present?
      assert_equal "Changes must be made through a pull request.", run&.message
    end

    test "Integration test: fails Ref#update without pull request for required pull request rule" do
      @review_protected_branch.required_approving_review_count = 0
      @review_protected_branch.save!

      @pull.destroy

      commit = @review_repo.commits.create({ message: "hello", author: @user }, @review_repo.default_branch_ref.target_oid) do |files|
        files.add("file1", "content1")
      end
      exception = assert_raises(Git::Ref::ProtectedBranchUpdateError) do
        @review_repo.heads.find("master").update(commit, @user)
      end
      assert_match(/Changes must be made through a pull request/, exception.message)
    end

    test "Integration test: passes Ref#update with pull request for required pull request rule" do
      @review_protected_branch.required_approving_review_count = 0
      @review_protected_branch.save!

      result = @pull.merge

      assert result[0]
    end

    test "fails for user when branch is locked for non-admins" do
      review = create(:pull_request_review, pull_request: @pull, user: @reviewer)
      review.approve!

      @review_protected_branch.lock_branch_enforcement_level = :non_admins
      @review_protected_branch.save!

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal "lock_branch", decision.failed_rule_types.first

      # cannot override as non-admin
      refute decision.can_bypass_rule_type?(:lock_branch)
    end

    test "passes for admin when branch is locked for non-admins" do
      review = create(:pull_request_review, pull_request: @pull, user: @reviewer)
      review.approve!

      @review_protected_branch.lock_branch_enforcement_level = :non_admins
      @review_protected_branch.save!

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)

      # Evaluation indicates the policy is not fulfilled
      # requires an override
      refute_predicate decision, :rules_fulfilled?

      # Decision is overridable
      assert decision.can_bypass_rule_type?(:lock_branch)
      assert decision.action_permitted?
      assert_equal "lock_branch", decision.failed_rule_types.first
    end

    test "fails for admin when branch is locked everyone" do
      review = create(:pull_request_review, pull_request: @pull, user: @reviewer)
      review.approve!

      # locks for everyone
      @review_protected_branch.enable_lock_branch
      @review_protected_branch.save!

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal "lock_branch", decision.failed_rule_types.first

      # Decision is not overridable
      refute decision.can_bypass_rule_type?(:lock_branch)
    end

    context "admin overrides" do
      test "denies admin override when there are no reviews, required status checks pending, merge commits and no overrides allowed" do
        @review_protected_branch.pull_request_reviews_enforcement_level = :everyone
        @review_protected_branch.linear_history_requirement_enforcement_level = :everyone
        @review_protected_branch.update_required_status_checks(include_admins: true, contexts: %w[foo])
        @review_protected_branch.save!

        merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
        ref_update = create_branch_update(@review_repo,
          name: "master",
          before_oid: @review_repo.heads["master"].target_oid,
          after_oid: merge_commit.oid)

        create :status, repository: @review_repo, creator: @user, sha: @review_repo.heads["cr-line-endings"].target_oid, context: "foo", state: "pending"

        decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)

        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:required_status_checks)
        refute decision.can_bypass_rule_type?(:pull_request)
        refute decision.can_bypass_rule_type?(:required_linear_history)
        refute decision.action_permitted?
      end

      test "denies admin override when there are no reviews, required status checks pending and no required status check override allowed" do
        @review_protected_branch.pull_request_reviews_enforcement_level = :non_admins
        @review_protected_branch.linear_history_requirement_enforcement_level = :non_admins
        @review_protected_branch.update_required_status_checks(include_admins: true, contexts: %w[foo])
        @review_protected_branch.save!

        merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
        ref_update = create_branch_update(@review_repo,
          name: "master",
          before_oid: @review_repo.heads["master"].target_oid,
          after_oid: merge_commit.oid)

        create :status, repository: @review_repo, creator: @user, sha: @review_repo.heads["cr-line-endings"].target_oid, context: "foo", state: "pending"

        decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)

        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:required_status_checks)
        refute decision.can_bypass_rule_type?(:pull_request)
        refute decision.can_bypass_rule_type?(:required_linear_history)
        refute decision.action_permitted?
      end

      test "denies admin override when there are no reviews, required status checks pending and no review policy override allowed" do
        @review_protected_branch.update_required_status_checks(include_admins: true, contexts: %w[foo])
        @review_protected_branch.pull_request_reviews_enforcement_level = :everyone
        @review_protected_branch.linear_history_requirement_enforcement_level = :everyone
        @review_protected_branch.save!

        merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
        ref_update = create_branch_update(@review_repo,
          name: "master",
          before_oid: @review_repo.heads["master"].target_oid,
          after_oid: merge_commit.oid)

        create :status, repository: @review_repo, creator: @user, sha: @review_repo.heads["cr-line-endings"].target_oid, context: "foo", state: "pending"

        decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)

        refute_predicate decision, :rules_fulfilled?
        refute decision.can_bypass_rule_type?(:required_status_checks)
        refute decision.can_bypass_rule_type?(:pull_request)
        refute decision.can_bypass_rule_type?(:required_linear_history)
        refute decision.action_permitted?
      end

      test "denies admin override when there are no reviews, required status checks pending, merge commits, and the branch is locked" do
        @review_protected_branch.lock_branch_enforcement_level = :everyone
        @review_protected_branch.pull_request_reviews_enforcement_level = :non_admins
        @review_protected_branch.linear_history_requirement_enforcement_level = :non_admins
        @review_protected_branch.update_required_status_checks(contexts: %w[foo])
        @review_protected_branch.save!

        merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
        ref_update = create_branch_update(@review_repo,
          name: "master",
          before_oid: @review_repo.heads["master"].target_oid,
          after_oid: merge_commit.oid)

        create :status, repository: @review_repo, creator: @user, sha: @review_repo.heads["cr-line-endings"].target_oid, context: "foo", state: "pending"

        decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)

        refute_predicate decision, :rules_fulfilled?
        assert decision.can_bypass_rule_type?(:required_status_checks)
        assert decision.can_bypass_rule_type?(:pull_request)
        assert decision.can_bypass_rule_type?(:required_linear_history)
        refute decision.can_bypass_rule_type?(:lock_branch)
        refute decision.action_permitted?
      end

      test "allows admin override when there are no reviews, required status checks pending, merge commits, and overrides are allowed" do
        @review_protected_branch.pull_request_reviews_enforcement_level = :non_admins
        @review_protected_branch.linear_history_requirement_enforcement_level = :non_admins
        @review_protected_branch.update_required_status_checks(include_admins: false, contexts: %w[foo])
        @review_protected_branch.save!

        merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
        ref_update = create_branch_update(@review_repo,
          name: "master",
          before_oid: @review_repo.heads["master"].target_oid,
          after_oid: merge_commit.oid)

        create :status, repository: @review_repo, creator: @user, sha: @review_repo.heads["cr-line-endings"].target_oid, context: "foo", state: "pending"

        decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)

        refute_predicate decision, :rules_fulfilled?
        assert decision.can_bypass_rule_type?(:required_status_checks)
        assert decision.can_bypass_rule_type?(:pull_request)
        assert decision.can_bypass_rule_type?(:required_linear_history)
        assert decision.action_permitted?
      end

      test "allows admin override when there are no reviews, required status checks pending, merge commits, the branch is locked, and overrides allowed" do
        @review_protected_branch.lock_branch_enforcement_level = :non_admins
        @review_protected_branch.pull_request_reviews_enforcement_level = :non_admins
        @review_protected_branch.linear_history_requirement_enforcement_level = :non_admins
        @review_protected_branch.update_required_status_checks(include_admins: false, contexts: %w[foo])
        @review_protected_branch.save!

        merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
        ref_update = create_branch_update(@review_repo,
          name: "master",
          before_oid: @review_repo.heads["master"].target_oid,
          after_oid: merge_commit.oid)

        create :status, repository: @review_repo, creator: @user, sha: @review_repo.heads["cr-line-endings"].target_oid, context: "foo", state: "pending"

        decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)

        refute_predicate decision, :rules_fulfilled?
        assert decision.can_bypass_rule_type?(:required_status_checks)
        assert decision.can_bypass_rule_type?(:pull_request)
        assert decision.can_bypass_rule_type?(:required_linear_history)
        assert decision.can_bypass_rule_type?(:lock_branch)
        assert decision.action_permitted?
      end
    end
  end

  context "individual policy overrides" do
    test "enforce all policies when a user can override an individual policy" do
      @review_protected_branch.pull_request_reviews_enforcement_level = :non_admins
      @review_protected_branch.replace_branch_actor_allowances(:pull_request, user_ids: [@user.id], team_ids: [], integration_ids: [])
      @review_protected_branch.signature_requirement_enforcement_level = :non_admins
      @review_protected_branch.save!

      merge_commit = @review_repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@review_repo,
        name: "master",
        before_oid: @review_repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      assert decision.can_bypass_rule_type?(:pull_request)
      refute decision.can_bypass_rule_type?(:required_signatures)
      refute decision.action_permitted?
    end
  end

  test "does not calculate fast-forward status if precomputed for update with no required statuses" do
    ref_update = create_branch_update(
      @repo, name: "master",
      before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
      after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
      fast_forward: true
    )

    GitRPC::Client.any_instance.expects(:descendant_of).never
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert decision.rules_fulfilled?, "check failed: #{decision}"
    assert_nil decision.message
  end

  test "does calculate fast-forward status if not precomputed for update with no required statuses" do
    ref_update = create_branch_update(
      @repo, name: "master",
      before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
      after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"
    )

    GitRPC::Client.any_instance.expects(:descendant_of).once.
      with([[ref_update.after_oid, ref_update.before_oid]]).
      returns({ [ref_update.after_oid, ref_update.before_oid] => true })
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert decision.rules_fulfilled?, "check failed: #{decision}"
    assert_nil decision.message
  end


  test "succeeds for fast-forward update with no required statuses" do
    ref_update = create_branch_update(@repo, name: "master",
                                      before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                      after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert decision.rules_fulfilled?, "check failed: #{decision}"
    assert_nil decision.message
  end

  test "succeeds for fast-forward update with passing required statuses" do
    @protected_branch.replace_status_contexts(%w[foo bar])
    create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "foo", state: "success"
    create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "bar", state: "success"

    ref_update = create_branch_update(@repo, name: "master",
                                      before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                      after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert decision.rules_fulfilled?, "check failed: #{decision} - #{decision.failed_rule_types}"
    assert_nil decision.message
  end

  test "succeeds for fast-forward update with passing required check runs and a failing non-required check-run" do
    commit = @repo.heads.find("master").commit

    check_suite = create(:check_suite, repository: @repo, github_app: @github_app, head_sha: commit.oid)
    check_run1  = create(:check_run, name: "foo", check_suite: check_suite, status: :completed, completed_at: Time.now, conclusion: :success)
    check_run2  = create(:check_run, name: "bar", check_suite: check_suite, status: :completed, completed_at: Time.now, conclusion: :success)
    check_run3  = create(:check_run, name: "baz", check_suite: check_suite, status: :completed, completed_at: Time.now, conclusion: :failure)

    @protected_branch.replace_status_contexts(%w[foo bar])

    ref_update = create_branch_update(@repo, name: "master",
                                      before_oid: commit.first_parent_oid,
                                      after_oid: commit.oid)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert_predicate decision, :rules_fulfilled?, "check failed: #{decision} - #{decision.failed_rule_types}"
    assert_nil decision.message
  end

  test "succeeds for fast-forward update by repo admin with one expected required status" do
    @protected_branch.replace_status_contexts(%w[foo])

    ref_update = create_branch_update(@repo, name: "master",
                                      before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                      after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

    refute decision.rules_fulfilled?, "check failed: #{decision}"
    assert decision.action_permitted?, "check failed: #{decision}"
    assert_equal "Required status check \"foo\" is expected.", decision.message
  end

  test "succeeds for updates with same trees but different commits" do
    @protected_branch.replace_status_contexts(%w[foo])

    branch_one = @repo.refs.find("cr-line-endings")
    branch_two = @repo.refs.create("refs/heads/cr-line-endings-two", branch_one.target_oid, @user)
    branch_two.append_commit({ message: "Empty commit", committer: @user }, @user)

    assert_equal branch_one.target.tree_oid, branch_two.target.tree_oid # sanity check

    create :status, repository: @repo, creator: @user, sha: branch_one.target_oid, context: "foo", state: "success"
    create :status, repository: @repo, creator: @user, sha: branch_two.target_oid, context: "foo", state: "failure"

    merge_commit = @repo.commits.create_merge_commit(@user, "master", branch_one.name).first
    ref_update = create_branch_update(@repo,
      name: "master",
      before_oid: @repo.heads["master"].target_oid,
      after_oid: merge_commit.oid)

    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

    assert decision.rules_fulfilled?, "check failed: #{decision} - #{decision.failed_rule_types}"
    assert_nil decision.message
  end

  test "succeeds for branch deletions with required statuses" do
    @protected_branch.clear_blocked_deletions
    @protected_branch.replace_status_contexts(%w[foo bar])
    @protected_branch.save!

    ref_update = create_branch_update(@repo, name: "master",
                                      before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                      after_oid: GitHub::NULL_OID)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert_predicate decision, :rules_fulfilled?
    assert_nil decision.message
  end

  test "fails for fast-forward update with one expected required status" do
    @protected_branch.replace_status_contexts(%w[foo])

    ref_update = create_branch_update(@repo, name: "master",
                                      before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                      after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    refute decision.rules_fulfilled?, "check passed: #{decision}"
    assert_equal "Required status check \"foo\" is expected.", decision.message
  end

  test "fails for fast-forward update with multiple failed required statuses" do
    @protected_branch.replace_status_contexts(%w[foo bar baz])

    create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "foo", state: "failure"
    create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "bar", state: "failure"
    create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "baz", state: "success"

    ref_update = create_branch_update(@repo, name: "master",
                                      before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                      after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    refute decision.rules_fulfilled?, "check passed: #{decision}"
    assert_equal "2 of 3 required status checks are failing.", decision.message
  end

  test "fails for fast-forward update with mixed required statuses" do
    @protected_branch.replace_status_contexts(%w[foo bar baz quux])
    create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "bar", state: "failure"
    create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "baz", state: "failure"
    create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "quux", state: "error"

    ref_update = create_branch_update(@repo, name: "master",
                                      before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                      after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    refute decision.rules_fulfilled?, "check passed: #{decision}"
    assert_equal "4 of 4 required status checks have not succeeded: 1 expected, 1 errored, and 2 failing.", decision.message
  end

  test "fails for non-fast-forward update" do
    ref_update = create_branch_update(@repo, name: "master",
                                      before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                      after_oid: "63611721afd41f58f801d66e543d8288b4c5eb44")
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    refute decision.rules_fulfilled?, "check passed: #{decision}"
    assert_equal "Cannot force-push to this #{ref_update.ref_type != "unknown" ? ref_update.ref_type : 'ref'}", decision.message
  end

  test "determines rejection basis commit as branch HEAD commit when statuses are stored there" do
    @protected_branch.replace_status_contexts(%w[foo bar baz])
    pull = PullRequest.create_for!(@repo,
      base: "master",
      head: "cr-line-endings",
      user: @user,
      title: "title",
      body: "body",
    )

    pull.create_merge_commit

    create :status, repository: @repo, creator: @user, sha: pull.head_sha, context: "foo", state: "failure"
    create :status, repository: @repo, creator: @user, sha: pull.head_sha, context: "bar", state: "failure"
    create :status, repository: @repo, creator: @user, sha: pull.head_sha, context: "baz", state: "success"

    pr_merge_ref_update = create_branch_update(@repo, name: "master",
                                               before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", # master~
                                               after_oid: pull.merge_commit_sha)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, pr_merge_ref_update, @user)

    refute decision.rules_fulfilled?, "check passed: #{decision}"
    assert_equal 1, decision.failed_rule_types.size
    assert_equal pull.head_sha, decision.runs_by_rule_type("required_status_checks").first&.basis_commit.sha
  end

  test "determines rejection basis commit as PR merge commit when statuses are stored there" do
    @protected_branch.replace_status_contexts(%w[foo bar baz])

    pull = PullRequest.create_for!(@repo,
      base: "master",
      head: "cr-line-endings",
      user: @user,
      title: "title",
      body: "body",
    )
    pull.create_merge_commit

    create :status, repository: @repo, creator: @user, sha: pull.merge_commit_sha, context: "foo", state: "failure"
    create :status, repository: @repo, creator: @user, sha: pull.merge_commit_sha, context: "bar", state: "failure"
    create :status, repository: @repo, creator: @user, sha: pull.merge_commit_sha, context: "baz", state: "success"

    pr_merge_ref_update = create_branch_update(@repo, name: "master",
                                               before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", # master
                                               after_oid: pull.merge_commit_sha)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, pr_merge_ref_update, @user)

    refute decision.rules_fulfilled?, "check passed: #{decision}"
    assert_equal 1, decision.failed_rule_types.size
    assert_equal pull.merge_commit_sha, decision.runs_by_rule_type("required_status_checks").first&.basis_commit.sha
  end

  test "allows ref update when successful statuses posted to PR merge commit" do
    @protected_branch.replace_status_contexts(%w[foo bar baz])

    pull = PullRequest.create_for!(@repo,
      base: "master",
      head: "cr-line-endings",
      user: @user,
      title: "title",
      body: "body",
    )
    pull.create_merge_commit

    create :status, repository: @repo, creator: @user, sha: pull.merge_commit_sha, context: "foo", state: "success"
    create :status, repository: @repo, creator: @user, sha: pull.merge_commit_sha, context: "bar", state: "success"
    create :status, repository: @repo, creator: @user, sha: pull.merge_commit_sha, context: "baz", state: "success"

    pr_merge_ref_update = create_branch_update(@repo, name: "master",
                                               before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", # master
                                               after_oid: pull.merge_commit_sha)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, pr_merge_ref_update, @user)

    assert decision.rules_fulfilled?, "check failed: #{decision}"
  end

  test "merge commit gets precedence over PR head" do
    # This test demonstrates a curious aspect of how real world merge statuses
    # work.  Since the prospective merge commit (merge_commit_sha) is passed as
    # the after_commit for the Ref::Update to be evaulated (which is thus the
    # policy commit for policy purposes), statuses posted to the merge commit
    # are considered first, causing statuses, even failing ones, posted to the
    # head commit to be ignored.  See
    # https://github.com/github/github/pull/133680 for more info.
    @protected_branch.replace_status_contexts(%w[foo])

    pull = PullRequest.create_for!(@repo,
      base: "master",
      head: "cr-line-endings",
      user: @user,
      title: "title",
      body: "body",
    )
    pull.create_merge_commit

    create :status, repository: @repo, creator: @user, sha: pull.merge_commit_sha, context: "foo", state: "success"

    # Create a status that would normally block the update but will be
    # ignored because of the status on the merge.
    create :status, repository: @repo, creator: @user, sha: pull.head_sha, context: "foo", state: "failure"

    pr_merge_ref_update = create_branch_update(@repo, name: "master",
                                               before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", # master
                                               after_oid: pull.merge_commit_sha)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, pr_merge_ref_update, @user)

    assert decision.rules_fulfilled?, "check failed: #{decision}"
  end

  test "allows ref update when successful statuses posted to PR head commit" do
    @protected_branch.replace_status_contexts(%w[foo bar baz])

    pull = PullRequest.create_for!(@repo,
      base: "master",
      head: "cr-line-endings",
      user: @user,
      title: "title",
      body: "body",
    )
    pull.create_merge_commit

    create :status, repository: @repo, creator: @user, sha: pull.head_sha, context: "foo", state: "success"
    create :status, repository: @repo, creator: @user, sha: pull.head_sha, context: "bar", state: "success"
    create :status, repository: @repo, creator: @user, sha: pull.head_sha, context: "baz", state: "success"

    pr_merge_ref_update = create_branch_update(@repo, name: "master",
                                               before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", # master
                                               after_oid: pull.merge_commit_sha)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, pr_merge_ref_update, @user)

    assert decision.rules_fulfilled?, "check failed: #{decision}"
  end

  test "can check multiple ref updates" do
    @repo.protect_branch("cr-line-endings", creator: @user, required_status_checks: { include_admins: true }, entry_point: :test_case)

    ref_updates = [
      create_branch_update(@repo, name: "cr-line-endings", before_oid: @repo.heads["cr-line-endings"].target_oid, after_oid: GitHub::NULL_OID),
      create_branch_update(@repo, name: "master", before_oid: @repo.heads["master"].target_oid, after_oid: @repo.heads["cr-line-endings"].target_oid),
      create_tag_update(@repo, name: "foo", before_oid: GitHub::NULL_OID, after_oid: @repo.heads["master"].target_oid),
    ]
    decisions = RuleEngine::Evaluator.evaluate_rules(@repo, ref_updates, @user)

    assert_equal 3, decisions.length
    decision0, decision1, decision2 = T.must(decisions[0]), T.must(decisions[1]), T.must(decisions[2])
    refute decision0.rules_fulfilled?, "cr-line-endings check passed: #{decision0}"
    assert_equal "Cannot delete this branch", decision0.message
    assert decision1.rules_fulfilled?, "master check failed: #{decision1}"
    assert_nil decision1.message
    assert decision2.rules_fulfilled?, "tags/foo check failed: #{decision2}"
    assert_nil decision2.message
  end

  test "can check multiple ref updates: all are covered by the same branch protection rule" do
    ref = @repo.heads.create("feature-a", @repo.heads["master"].target.first_parent_oid, @user)
    commit = ref.append_commit({ message: "commit", committer: @user }, @user) do |files|
      files.add "file-a", "some content"
    end
    new_commit_a = @repo.commits.create({ message: "commit", committer: @user }, commit.oid) do |files|
      files.add "file-a", "some updated content"
    end
    ref = @repo.heads.create("feature-b", @repo.heads["master"].target.first_parent_oid, @user)
    commit = ref.append_commit({ message: "commit", committer: @user }, @user) do |files|
      files.add "file-b", "some content"
    end
    new_commit_b = @repo.commits.create({ message: "commit", committer: @user }, commit.oid) do |files|
      files.add "file-b", "some updated content"
    end

    @repo.protect_branch("feature-*", creator: @user, required_status_checks: { contexts: ["foo"], include_admins: true }, entry_point: :test_case)

    ref_updates = [
      create_branch_update(@repo, name: "feature-a", before_oid: @repo.heads["feature-a"].target_oid, after_oid: new_commit_a.oid),
      create_branch_update(@repo, name: "feature-b", before_oid: @repo.heads["feature-b"].target_oid, after_oid: new_commit_b.oid),
    ]
    decisions = RuleEngine::Evaluator.evaluate_rules(@repo, ref_updates, @user)

    assert_equal 2, decisions.size
    assert_equal 0, decisions.count(&:rules_fulfilled?)
  end

  test "can check multiple ref updates: one passing and one failing status check" do
    @repo.protect_branch("-gh-pages", creator: @user, required_status_checks: { include_admins: true, contexts: %w[ci/janky ci/pages] }, entry_point: :test_case)
    @protected_branch.replace_status_contexts(%w[ci/janky])
    create :status, repository: @repo, creator: @user, sha: @repo.heads["cr-line-endings"].target_oid, context: "ci/janky", state: "success"

    ref_updates = [
      # Can push master forward to cr-line-endings
      create_branch_update(@repo, name: "master", before_oid: @repo.heads["master"].target_oid, after_oid: @repo.heads["cr-line-endings"].target_oid),
      # Cannot push -gh-pages forward to cr-line-endings
      create_branch_update(@repo, name: "-gh-pages", before_oid: @repo.heads["-gh-pages"].target_oid, after_oid: @repo.heads["cr-line-endings"].target_oid),
    ]
    decisions = RuleEngine::Evaluator.evaluate_rules(@repo, ref_updates, @user)

    assert_equal 2, decisions.length
    decision0, decision1 = T.must(decisions[0]), T.must(decisions[1])
    assert decision0.rules_fulfilled?, "master check failed: #{decision0.inspect}"
    assert_nil decision0.message
    refute decision1.rules_fulfilled?, "-gh-pages check passed: #{decision1.inspect}"
    assert_equal "Required status check \"ci/pages\" is expected.", decision1.message
  end

  test "can check multiple ref updates: one force-push and one normal push" do
    @repo.protect_branch("cr-line-endings", creator: @user, required_status_checks: { include_admins: true }, entry_point: :test_case)

    ref_updates = [
      # Can push master forward to cr-line-endings
      create_branch_update(@repo, name: "master", before_oid: @repo.heads["master"].target_oid, after_oid: @repo.heads["cr-line-endings"].target_oid),
      # Cannot push cr-line-endings backward to master
      create_branch_update(@repo, name: "cr-line-endings", before_oid: @repo.heads["cr-line-endings"].target_oid, after_oid: @repo.heads["master"].target_oid),
    ]
    decisions = RuleEngine::Evaluator.evaluate_rules(@repo, ref_updates, @user)

    assert_equal 2, decisions.length
    decision0, decision1 = T.must(decisions[0]), T.must(decisions[1])
    assert decision0.rules_fulfilled?, "master check failed: #{decision0.inspect}"
    assert_nil decision0.message
    refute decision1.rules_fulfilled?, "cr-line-endings check passed: #{decision1.inspect}"
    assert_equal "Cannot force-push to this branch", decision1.message
  end

  test "can check multiple ref updates: identical force-pushes for different branches" do
    branches = %w[branch1 branch2 branch3]

    target_oid = @repo.heads["master"].target_oid
    branches.each do |branch|
      @repo.heads.create(branch, target_oid, @user)
      @repo.protect_branch(branch, creator: @user, required_status_checks: { include_admins: true }, entry_point: :test_case)
    end

    # Force-push all branches back to v2.
    ref_updates = branches.map do |branch|
      create_branch_update(@repo, name: "#{branch}", before_oid: target_oid, after_oid: @repo.tags["v2"].target_oid)
    end
    decisions = RuleEngine::Evaluator.evaluate_rules(@repo, ref_updates, @user)

    assert_equal [false, false, false], decisions.map(&:rules_fulfilled?)
    assert_equal %w[non_fast_forward non_fast_forward non_fast_forward], decisions.flat_map(&:failed_rule_types)
  end

  test "can check multiple ref updates: one requires status checks for admins and one doesn't" do
    @repo.protect_branch("-gh-pages", creator: @user, required_status_checks: { include_admins: true, contexts: %w[ci/janky] }, entry_point: :test_case)
    @protected_branch.replace_status_contexts(%w[ci/janky])

    ref_updates = [
      # Can push master forward to cr-line-endings
      create_branch_update(@repo, name: "master", before_oid: @repo.heads["master"].target_oid, after_oid: @repo.heads["cr-line-endings"].target_oid),
      # Cannot push -gh-pages forward to cr-line-endings
      create_branch_update(@repo, name: "-gh-pages", before_oid: @repo.heads["-gh-pages"].target_oid, after_oid: @repo.heads["cr-line-endings"].target_oid),
    ]
    decisions = RuleEngine::Evaluator.evaluate_rules(@repo, ref_updates, @repo.owner)

    assert_equal 2, decisions.length

    decision0, decision1 = T.must(decisions[0]), T.must(decisions[1])
    refute decision0.rules_fulfilled?, "master check failed: #{decision0.inspect}"
    assert decision0.action_permitted?, "master merge allowed: #{decision0.inspect}"
    assert_equal "Required status check \"ci/janky\" is expected.", decision0.message

    refute decision1.rules_fulfilled?, "-gh-pages check passed: #{decision1.inspect}"
    refute decision1.action_permitted?, "-gh-pages merge denied: #{decision0.inspect}"
    assert_equal "Required status check \"ci/janky\" is expected.", decision1.message
  end

  context "with a glob pattern" do
    test "fails when refname matches prefix" do
      @protected_branch.update!(name: "ma*")

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: GitHub::NULL_OID)
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal "Cannot delete this #{ref_update.ref_type != "unknown" ? ref_update.ref_type : 'ref'}", decision.message
    end

    test "passes when refname does not match prefix" do
      @protected_branch.update!(name: "master1*")

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: GitHub::NULL_OID)
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      assert decision.rules_fulfilled?, "check failed: #{decision}"
      assert_nil decision.message
    end
  end

  context "with authorized users and teams specified" do
    test "fails for non-specified users when fast-forward update with no required statuses" do
      @org_protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)
      @org_protected_branch.reload

      refute_empty @org_protected_branch.authorized_actors

      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @user)

      refute result.action_permitted?, "check succeeded: #{result}"
      assert_equal "You're not authorized to push to this branch. Visit #{DocsUrlConfig.url_for("repositories/about-protected-branches")} for more information.", result.message
    end

    test "fails for non-specified users when fast-forward update with passing required statuses" do
      @org_protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)
      @org_protected_branch.reload
      refute_empty @org_protected_branch.authorized_actors

      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      create :status, repository: @org_repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "foo", state: "success"
      create :status, repository: @org_repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "bar", state: "success"

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @user)

      refute result.action_permitted?, "check succeeded: #{result}"
      assert_equal "You're not authorized to push to this branch. Visit #{DocsUrlConfig.url_for("repositories/about-protected-branches")} for more information.", result.message
    end

    test "works for specified users when fast-forward update with no required statuses" do
      @org_protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)
      @org_protected_branch.reload

      refute_empty @org_protected_branch.authorized_actors

      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @org_admin)

      assert result.action_permitted?, "check failed: #{result}"
      assert_nil result.message
    end

    test "works for specified team members when fast-forward update with no required statuses" do
      member = create(:user)
      team = create(:team, organization: @org)
      team.add_member member
      team.add_repository @org_repo, :admin

      @org_protected_branch.replace_authorized_actors(user_ids: [], team_ids: [team.id], entry_point: :test_case)
      @org_protected_branch.reload

      refute_empty @org_protected_branch.authorized_actors

      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, member)

      assert result.action_permitted?, "check failed: #{result}"
      assert_nil result.message
    end

    test "works for specified integration installations when fast-forward update with no required statuses" do
      app = create(:integration)
      org_repo_app_installation = make_integration_installation(integration: app, repository: @org_repo, permissions: { "contents" => :write })
      bot = org_repo_app_installation.bot
      @org_protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], integration_ids: [app.id], entry_point: :test_case)
      @org_protected_branch.reload

      refute_empty @org_protected_branch.authorized_actors

      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, bot)

      assert result.action_permitted?, "check failed: #{result}"
      assert_nil result.message
    end

    test "works for specified users when fast-forward update with passing required statuses" do
      @org_protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)
      @org_protected_branch.reload
      refute_empty @org_protected_branch.authorized_actors

      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      create :status, repository: @org_repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "foo", state: "success"
      create :status, repository: @org_repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "bar", state: "success"

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @org_admin)

      assert result.action_permitted?, "check failed: #{result}"
      assert_nil result.message
    end

    test "org admins can always push" do
      user = create(:user)
      @org_repo.add_member user, action: :write

      @org_protected_branch.replace_authorized_actors(user_ids: [user.id], team_ids: [], entry_point: :test_case)
      @org_protected_branch.reload

      refute_empty @org_protected_branch.authorized_actors
      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @org_admin)

      assert result.action_permitted?, "check failed: #{result}"
      assert_nil result.message
    end

    test "users with repo admin access can always push" do
      repo_admin = create(:user)
      @org_repo.add_member repo_admin, action: :admin

      @org_protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)
      @org_protected_branch.reload

      refute_empty @org_protected_branch.authorized_actors
      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, repo_admin)

      assert result.action_permitted?, "check failed: #{result}"
      assert_nil result.message
    end

    test "users with repo maintain access can always push" do
      repo_maintainer = create(:user)
      @org_repo.add_member repo_maintainer, action: :maintain

      # configure branch protection with push restrictions
      @org_protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)
      @org_protected_branch.reload

      refute_empty @org_protected_branch.authorized_actors
      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@org_repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")

      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, repo_maintainer)
      assert result.action_permitted?, "check failed: #{result}; #{result.message}"
      assert_nil result.message
    end

    test "members of teams with repo admin access can always push" do
      team_member = create(:user)
      team = create(:team, organization: @org)
      team.add_member team_member
      team.add_repository @org_repo, :admin

      @org_protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)
      @org_protected_branch.reload

      refute_empty @org_protected_branch.authorized_actors
      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, team_member)

      assert result.action_permitted?, "check failed: #{result}"
      assert_nil result.message
    end

    test "works when the actor is a public key" do
      user = create(:user)
      public_key  = create :public_key, user: user
      @org_repo.add_member user, action: :write

      @org_protected_branch.replace_authorized_actors(user_ids: [user.id], team_ids: [], entry_point: :test_case)
      @org_protected_branch.reload

      refute_empty @org_protected_branch.authorized_actors
      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, public_key)

      assert result.action_permitted?, "check failed: #{result}"
      assert_nil result.message
    end

    test "can push with deploy key as if it was a repo admin" do
      disable_feature_flag(:report_authzd_indeterminates) # this test fails when authzd raises errors
      read_deploy_key = create :public_key, repository: @org_repo, read_only: true
      write_deploy_key  = create :public_key, repository: @org_repo, read_only: false

      @org_protected_branch.replace_authorized_actors(user_ids: [], team_ids: [], entry_point: :test_case)
      @org_protected_branch.reload

      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")

      decision = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, read_deploy_key)
      refute decision.action_permitted?, "check passed: #{decision}"
      assert_equal "You're not authorized to push to this branch. Visit #{DocsUrlConfig.url_for("repositories/about-protected-branches")} for more information.", decision.message

      decision = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, write_deploy_key)
      assert decision.action_permitted?, "check failed: #{decision}"
      assert_nil decision.message
    end

    test "fails for non-specified users when branch deletion" do
      @org_protected_branch.clear_blocked_deletions
      @org_protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)

      refute_empty @org_protected_branch.authorized_actors
      assert_predicate @org_protected_branch, :has_authorized_actors?

      @org_protected_branch.save

      ref_update = create_branch_update(@org_repo, name: "master",
                                        before_oid: @org_repo.heads["master"].sha,
                                        after_oid: GitHub::NULL_OID)
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @user)

      refute result.action_permitted?
      assert_equal "You're not authorized to push to this branch. Visit #{DocsUrlConfig.url_for("repositories/about-protected-branches")} for more information.", result.message
    end

    test "succeeds for specified users when branch deletion" do
      @org_protected_branch.clear_blocked_deletions
      @org_protected_branch.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)
      @org_protected_branch.save!

      refute_empty @org_protected_branch.authorized_actors

      assert_predicate @org_protected_branch, :has_authorized_actors? # sanity check

      ref_update = create_branch_update(@org_repo, name: "master",
                                        before_oid: @org_repo.heads["master"].sha,
                                        after_oid: GitHub::NULL_OID)
      result = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @org_admin)

      assert result.action_permitted?
      assert_nil result.message
    end
  end

  context "required signatures" do
    test "unsigned commit allowed when signature requirement disabled" do
      @signature_required_branch.signature_requirement_enforcement_level = :off
      @signature_required_branch.save!

      ref_update = create_branch_update(
        @signature_required_repo,
        name: "master",
        before_oid: @unsigned_commit[:before],
        after_oid: @unsigned_commit[:after],
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@signature_required_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "unsigned commit rejected when signature requirement enabled" do
      ref_update = create_branch_update(
        @signature_required_repo,
        name: "master",
        before_oid: @unsigned_commit[:before],
        after_oid: @unsigned_commit[:after],
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@signature_required_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:required_signatures).find(&:failed?)
      assert run.present?
      assert_equal "Commits must have verified signatures.", run&.message
    end

    test "invalid signed commit rejected when signature requirement enabled" do
      ref_update = create_branch_update(
        @signature_required_repo,
        name: "master",
        before_oid: @invalid_signed_commit[:before],
        after_oid: @invalid_signed_commit[:after],
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@signature_required_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:required_signatures).find(&:failed?)
      assert run.present?
      assert_equal "Commits must have verified signatures.", run&.message
    end

    test "signed commit allowed when signature requirement enabled" do
      ref_update = create_branch_update(
        @signature_required_repo,
        name: "master",
        before_oid: @signed_commit[:before],
        after_oid: @signed_commit[:after],
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@signature_required_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "all commits in ref-update must be signed when required signatures enabled" do
      ref_update = create_branch_update(
        @signature_required_repo,
        name: "master",
        before_oid: @signed_and_unsigned_commits[:before],
        after_oid: @signed_and_unsigned_commits[:after],
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@signature_required_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:required_signatures).find(&:failed?)
      assert run.present?
      assert_equal "Commits must have verified signatures.", run&.message
    end

    test "branch deletion allowed" do
      @signature_required_branch.clear_blocked_deletions
      @signature_required_branch.save!

      ref_update = create_branch_update(
        @signature_required_repo,
        name: "master",
        before_oid: @signed_commit[:before],
        after_oid: GitHub::NULL_OID,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@signature_required_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end
  end

  context "merge commit blocking" do
    test "merge commit allowed when merge commits are not blocked" do
      @blocked_merge_commit_branch.linear_history_requirement_enforcement_level = :off
      @blocked_merge_commit_branch.save!

      ref_update = create_branch_update(
        @blocked_merge_commit_repo,
        name: "master",
        before_oid: @merge_update[:before],
        after_oid: @merge_update[:after],
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@blocked_merge_commit_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "merge commit rejected when merge commits are blocked" do
      ref_update = create_branch_update(
        @blocked_merge_commit_repo,
        name: "master",
        before_oid: @merge_update[:before],
        after_oid: @merge_update[:after],
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@blocked_merge_commit_repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal 1, decision.failed_rule_types.size

      run = decision.runs_by_rule_type(:required_linear_history).find(&:failed?)
      assert run.present?
      assert_equal "This branch must not contain merge commits.", run&.message
    end

    test "linear history allowed when merge commits are blocked" do
      ref_update = create_branch_update(
        @blocked_merge_commit_repo,
        name: "master",
        before_oid: @linear_update[:before],
        after_oid: @linear_update[:after],
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@blocked_merge_commit_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end

    test "branch deletion allowed" do
      @blocked_merge_commit_branch.clear_blocked_deletions
      @blocked_merge_commit_branch.save!

      ref_update = create_branch_update(
        @blocked_merge_commit_repo,
        name: "master",
        before_oid: @merge_update[:before],
        after_oid: GitHub::NULL_OID,
      )

      decision = RuleEngine::Evaluator.evaluate_rules_one(@blocked_merge_commit_repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert decision.action_permitted?
    end
  end

  context "branch deletion" do
    test "allowed when not blocked" do
      @protected_branch.clear_blocked_deletions
      @protected_branch.save!

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: GitHub::NULL_OID)
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert_nil decision.message
    end

    test "rejected when blocked" do
      assert_predicate @protected_branch, :block_deletions_enabled?

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: GitHub::NULL_OID)
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      assert_equal "Cannot delete this #{ref_update.ref_type != "unknown" ? ref_update.ref_type : 'ref'}", decision.message

      # rejects deletion by admin
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

      refute_predicate decision, :rules_fulfilled?
      assert_equal "Cannot delete this #{ref_update.ref_type != "unknown" ? ref_update.ref_type : 'ref'}", decision.message
    end
  end

  context "force pushes" do
    test "accepts a force push when allowed" do
      @protected_branch.clear_blocked_force_pushes
      @protected_branch.save!

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: "63611721afd41f58f801d66e543d8288b4c5eb44")
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert_nil decision.message
    end

    test "rejects a force push when not allowed" do
      assert_predicate @protected_branch, :block_force_pushes_enabled?

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: "63611721afd41f58f801d66e543d8288b4c5eb44")
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?, "check passed: #{decision}"
      assert_equal "Cannot force-push to this #{ref_update.ref_type != "unknown" ? ref_update.ref_type : 'ref'}", decision.message
    end

    test "accepts a force push using a write deploy key if the key's owner is allowed" do
      write_deploy_key = create :public_key, repository: @repo, read_only: false

      @protected_branch.enable_blocked_force_pushes
      @protected_branch.replace_branch_actor_allowances(:force_push, user_ids: [write_deploy_key.owner.id], team_ids: [], integration_ids: [])
      @protected_branch.save!

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: "63611721afd41f58f801d66e543d8288b4c5eb44")
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, write_deploy_key)

      assert decision.can_bypass_rule_type?(:non_fast_forward)

      refute_predicate decision, :rules_fulfilled?
    end

    test "rejects a force push from repo admins who are not explicitly allowed" do
      repo_admin = create :user
      @repo.add_member repo_admin, action: :admin
      @protected_branch.enable_blocked_force_pushes
      @protected_branch.replace_branch_actor_allowances(:force_push, user_ids: [@user.id], team_ids: [], integration_ids: [])
      @protected_branch.save!

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: "63611721afd41f58f801d66e543d8288b4c5eb44")
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, repo_admin)

      refute decision.can_bypass_rule_type?(:non_fast_forward)

      refute_predicate decision, :rules_fulfilled?
    end

    test "rejects a force push from org admins who are not explicitly allowed" do
      org_admin = create :user
      @org.add_admin org_admin
      @protected_branch.enable_blocked_force_pushes
      @protected_branch.replace_branch_actor_allowances(:force_push, user_ids: [@user.id], team_ids: [], integration_ids: [])
      @protected_branch.save!

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: "63611721afd41f58f801d66e543d8288b4c5eb44")
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, org_admin)

      refute decision.can_bypass_rule_type?(:non_fast_forward)

      refute_predicate decision, :rules_fulfilled?
    end
  end

  context "lock branch" do
    test "allow ref update when branch is not locked" do
      # default to not locked
      refute_predicate @protected_branch, :lock_branch_enabled?

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      assert_predicate decision, :rules_fulfilled?
      assert_nil decision.message
    end

    test "reject ref update for user when branch locked for non-admins" do
      # locks only for non-admins
      @protected_branch.enable_lock_branch
      @protected_branch.save!

      assert_equal "non_admins", @protected_branch.lock_branch_enforcement_level

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute_predicate decision, :rules_fulfilled?
      refute decision.action_permitted?
      assert_equal "Cannot change this locked branch", decision.message
      # cannot override
      refute decision.can_bypass_rule_type?(:lock_branch)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

      refute_predicate decision, :rules_fulfilled?
      assert_equal "lock_branch", decision.failed_rule_types.first

      # Decision is overridable by admin
      assert decision.can_bypass_rule_type?(:lock_branch)
      assert decision.action_permitted?
    end

    test "reject ref update when branch is locked for everyone" do
      # locks for everyone
      @protected_branch.lock_branch_enforcement_level = :everyone
      @protected_branch.save!

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)
      refute_predicate decision, :rules_fulfilled?
      refute decision.can_bypass_rule_type?(:lock_branch)
      refute decision.action_permitted?
      assert_equal "Cannot change this locked branch", decision.message

      # rejects update by admin
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)
      refute_predicate decision, :rules_fulfilled?
      refute decision.can_bypass_rule_type?(:lock_branch)
      refute decision.action_permitted?
      assert_equal "Cannot change this locked branch", decision.message
    end

    test "allow branch deletion when branch is not locked" do
      @protected_branch.clear_blocked_deletions
      @protected_branch.save!

      # default to not locked
      refute_predicate @protected_branch, :lock_branch_enabled?

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: GitHub::NULL_OID)
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)
      assert_predicate decision, :rules_fulfilled?
      assert_nil decision.message
    end

    test "reject branch deletion by user when branch is locked for non-admins" do
      @protected_branch.clear_blocked_deletions
      # A locked branch can't be deleted by anyone. even if enforcement level is non-admins
      @protected_branch.lock_branch_enforcement_level = :non_admins
      @protected_branch.save!

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: GitHub::NULL_OID)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)
      refute_predicate decision, :rules_fulfilled?
      assert_equal "Cannot change this locked branch", decision.message

      # allows deletion by admin
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)
      refute_predicate decision, :rules_fulfilled?
      assert decision.can_bypass_rule_type?(:lock_branch)
      assert decision.action_permitted?
    end

    test "reject branch deletion when branch is locked for everyone" do
      @protected_branch.clear_blocked_deletions
      # A locked branch can't be deleted by anyone. even if enforcement level is non-admins
      @protected_branch.lock_branch_enforcement_level = :everyone
      @protected_branch.save!

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: GitHub::NULL_OID)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)
      refute_predicate decision, :rules_fulfilled?
      refute decision.can_bypass_rule_type?(:lock_branch)
      refute decision.action_permitted?
      assert_equal "Cannot change this locked branch", decision.message

      # reject deletion by admin
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)
      refute_predicate decision, :rules_fulfilled?
      refute decision.can_bypass_rule_type?(:lock_branch)
      refute decision.action_permitted?
      assert_equal "Cannot change this locked branch", decision.message
    end
  end

  context "instrumentation" do
    test "includes org info in instrumentation event payload for org repos" do
      events = subscribe "protected_branch.rejected_ref_update"
      expected_message = "Cannot delete this branch"

      @org_protected_branch.replace_status_contexts(%w[foo bar baz quux])

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: GitHub::NULL_OID)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @user)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal expected_message, decision.message

      expected_payload = {
        branch: @org_protected_branch.qualified_name,
        repo: @org_protected_branch.repository.nwo,
        repo_id: @org_protected_branch.repository.id,
        public_repo: @org_protected_branch.repository.public?,
        actor: @user.name,
        actor_id: @user.id,
        reasons: [{
          code: :branch_deletion,
          message: expected_message,
        }],
        org: @org.name,
        org_id: @org.id,
        before: ref_update.before_oid,
        after: ref_update.after_oid,
        overridden_codes: [],
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments delete rejections" do
      events = subscribe "protected_branch.rejected_ref_update"
      expected_message = "Cannot delete this branch"

      @protected_branch.replace_status_contexts(%w[foo bar baz quux])

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: GitHub::NULL_OID)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal expected_message, decision.message

      expected_payload = {
        branch: @protected_branch.qualified_name,
        repo: @protected_branch.repository.nwo,
        repo_id: @protected_branch.repository.id,
        public_repo: @protected_branch.repository.public?,
        actor: @user.name,
        actor_id: @user.id,
        reasons: [{
          code: :branch_deletion,
          message: expected_message,
        }],
        before: ref_update.before_oid,
        after: ref_update.after_oid,
        overridden_codes: [],
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments force-push rejection" do
      events = subscribe "protected_branch.rejected_ref_update"
      expected_message = "Cannot force-push to this branch"

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: "63611721afd41f58f801d66e543d8288b4c5eb44")

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal expected_message, decision.message

      expected_payload = {
        branch: @protected_branch.qualified_name,
        repo: @protected_branch.repository.nwo,
        repo_id: @protected_branch.repository.id,
        public_repo: @protected_branch.repository.public?,
        actor: @user.name,
        actor_id: @user.id,
        reasons: [{
          code: :force_push,
          message: expected_message,
        }],
        before: ref_update.before_oid,
        after: ref_update.after_oid,
        overridden_codes: [],
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments failed required statuses" do
      events = subscribe "protected_branch.rejected_ref_update"
      expected_message = "Required status check \"foo\" is expected."

      @protected_branch.replace_status_contexts(%w[foo])

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal expected_message, decision.message

      expected_payload = {
        branch: @protected_branch.qualified_name,
        repo: @protected_branch.repository.nwo,
        repo_id: @protected_branch.repository.id,
        public_repo: @protected_branch.repository.public?,
        actor: @user.name,
        actor_id: @user.id,
        reasons: [{
          code: :required_status_checks,
          message: expected_message,
        }],
        failures_json: "[{\"foo\":\"expected\"}]",
        before: ref_update.before_oid,
        after: ref_update.after_oid,
        overridden_codes: [],
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments overrides for failed required statuses" do
      events = subscribe "protected_branch.policy_override"
      expected_message = "Required status check \"foo\" is expected."

      @protected_branch.replace_status_contexts(%w[foo])

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert decision.action_permitted?, "check passed: #{decision}"
      assert_equal expected_message, decision.message

      expected_payload = {
        branch: @protected_branch.qualified_name,
        repo: @protected_branch.repository.nwo,
        repo_id: @protected_branch.repository.id,
        public_repo: @protected_branch.repository.public?,
        actor: @repo.owner.name,
        actor_id: @repo.owner.id,
        before: ref_update.before_oid,
        after: ref_update.after_oid,
        reasons: [{
          code: :required_status_checks,
          message: expected_message,
        }],
        failures_json: "[{\"foo\":\"expected\"}]",
        overridden_codes: [:required_status_checks],
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments overrides for failed review policy" do
      events = subscribe "protected_branch.policy_override"
      expected_message = "Changes must be made through a pull request."

      @review_protected_branch.pull_request_reviews_enforcement_level = :non_admins
      @review_protected_branch.clear_required_status_checks
      @review_protected_branch.save!

      ref_update = create_branch_update(@review_repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert decision.action_permitted?, "check passed: #{decision}"
      assert_equal expected_message, decision.message

      expected_payload = {
        branch: @review_protected_branch.qualified_name,
        repo: @review_protected_branch.repository.nwo,
        repo_id: @review_protected_branch.repository.id,
        public_repo: @review_protected_branch.repository.public?,
        actor: @review_repo.owner.name,
        actor_id: @review_repo.owner.id,
        before: ref_update.before_oid,
        after: ref_update.after_oid,
        reasons: [{
          code: :review_policy_not_satisfied,
          message: expected_message,
        }],
        review_ids: [],
        approving_reviews_required: true,
        approving_reviews_count: 0,
        overridden_codes: [:review_policy_not_satisfied],
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments overrides for both, failed review policy and status checks" do
      events = subscribe "protected_branch.policy_override"
      expected_message = "Changes must be made through a pull request. Required status check \"foo\" is expected."

      @review_protected_branch.pull_request_reviews_enforcement_level = :non_admins
      @review_protected_branch.update_required_status_checks(include_admins: false, contexts: %w[foo])
      @review_protected_branch.save!

      ref_update = create_branch_update(@review_repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")

      decision = RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert decision.action_permitted?, "check passed: #{decision}"
      assert_equal expected_message, decision.message

      expected_payload = {
        branch: @review_protected_branch.qualified_name,
        repo: @review_protected_branch.repository.nwo,
        repo_id: @review_protected_branch.repository.id,
        public_repo: @review_protected_branch.repository.public?,
        actor: @review_repo.owner.name,
        actor_id: @review_repo.owner.id,
        before: ref_update.before_oid,
        after: ref_update.after_oid,
        reasons: [
          {
            code: :required_status_checks,
            message: "Required status check \"foo\" is expected.",
          },
          {
            code: :review_policy_not_satisfied,
            message: "Changes must be made through a pull request.",
          },
        ],
        review_ids: [],
        approving_reviews_required: true,
        approving_reviews_count: 0,
        failures_json: "[{\"foo\":\"expected\"}]",
        overridden_codes: [:review_policy_not_satisfied, :required_status_checks],
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments multiple failed required statuses" do
      events = subscribe "protected_branch.rejected_ref_update"
      expected_message = "4 of 4 required status checks have not succeeded: 1 expected, 1 errored, and 2 failing."

      @protected_branch.replace_status_contexts(%w[foo bar baz quux])
      create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "bar", state: "failure"
      create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "baz", state: "failure"
      create :status, repository: @repo, creator: @user, sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24", context: "quux", state: "error"

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal expected_message, decision.message

      expected_payload = {
        branch: @protected_branch.qualified_name,
        repo: @protected_branch.repository.nwo,
        repo_id: @protected_branch.repository.id,
        public_repo: @protected_branch.repository.public?,
        actor: @user.name,
        actor_id: @user.id,
        reasons: [{
          code: :required_status_checks,
          message: expected_message,
        }],
        failures_json: "[{\"bar\":\"failure\"},{\"baz\":\"failure\"},{\"foo\":\"expected\"},{\"quux\":\"error\"}]",
        before: ref_update.before_oid,
        after: ref_update.after_oid,
        overridden_codes: [],
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instrumentation sets actor and deploy key fingerprint when key is used" do
      write_deploy_key  = create :public_key, repository: @repo, read_only: false
      write_deploy_key.verify(@user)

      @protected_branch.update_required_status_checks(include_admins: false, contexts: %w[foo])
      @protected_branch.save!

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")

      # Check actor for both policy override and rejected ref events
      events = subscribe "protected_branch.policy_override"
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, write_deploy_key)
      assert decision.action_permitted?, "check passed: #{decision}"

      assert event = events.pop, "expected event"
      assert_equal write_deploy_key.verifier.name, event.payload[:actor]
      assert_equal write_deploy_key.verifier.id, event.payload[:actor_id]
      assert_equal write_deploy_key.fingerprint, event.payload[:deploy_key_fingerprint]

      events = subscribe "protected_branch.rejected_ref_update"
      @protected_branch.update_required_status_checks(include_admins: true, contexts: %w[foo])
      @protected_branch.save!

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, write_deploy_key)
      refute decision.action_permitted?, "check passed: #{decision}"

      assert event = events.pop, "expected event"
      assert_equal write_deploy_key.verifier.name, event.payload[:actor]
      assert_equal write_deploy_key.verifier.id, event.payload[:actor_id]
      assert_equal write_deploy_key.fingerprint, event.payload[:deploy_key_fingerprint]
    end

    test "instrumentation omits actor if deploy key is used and key verifier is missing" do
      write_deploy_key  = create :public_key, repository: @repo, read_only: false
      write_deploy_key.verify(@user)
      @user.destroy
      write_deploy_key.reload

      @protected_branch.update_required_status_checks(include_admins: false, contexts: %w[foo])
      @protected_branch.save!

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "63611721afd41f58f801d66e543d8288b4c5eb44",
                                        after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")

      # Check actor for both policy override and rejected ref events
      events = subscribe "protected_branch.policy_override"
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, write_deploy_key)
      assert decision.action_permitted?, "check passed: #{decision}"

      assert event = events.pop, "expected event"
      assert_nil event.payload[:actor]
      assert_nil event.payload[:actor_id]
      assert_equal write_deploy_key.fingerprint, event.payload[:deploy_key_fingerprint]

      events = subscribe "protected_branch.rejected_ref_update"
      @protected_branch.update_required_status_checks(include_admins: true, contexts: %w[foo])
      @protected_branch.save!

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, write_deploy_key)
      refute decision.action_permitted?, "check passed: #{decision}"

      assert event = events.pop, "expected event"
      assert_nil event.payload[:actor]
      assert_nil event.payload[:actor_id]
      assert_equal write_deploy_key.fingerprint, event.payload[:deploy_key_fingerprint]
    end

    test "doesn't instrument delete rejections with instrumentation disabled" do
      events = subscribe "protected_branch.rejected_ref_update"
      expected_message = "Cannot delete this branch"

      @protected_branch.replace_status_contexts(%w[foo bar baz quux])

      ref_update = create_branch_update(@repo, name: "master",
                                        before_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
                                        after_oid: GitHub::NULL_OID)
      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user, dry_run: true)

      refute decision.rules_fulfilled?, "check passed: #{decision}"
      assert_equal expected_message, decision.message

      refute events.pop, "expected no event"
    end

    test "logs additional information about the successful rule evaluation" do
      @protected_branch.clear_blocked_deletions
      @protected_branch.save!

      refname = "refs/heads/master"
      before_oid = "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"
      ref_update = create_ref_update(@repo, name: refname,
        before_oid: before_oid,
        after_oid: GitHub::NULL_OID)

      logger_output = {
        "Body": "Rule engine evaluation results",
        "gh.repo.id": @repo.id,
        "gh.actor.id": @user.id,
        "gh.actor.type": @user.class.name,
        "gh.branch_protection_rule.rule_suite.before_commit": before_oid,
        "gh.branch_protection_rule.rule_suite.after_commit": GitHub::NULL_OID,
        "gh.branch_protection_rule.rule_suite.ref_name": refname,
        "gh.branch_protection_rule.rule_suite.rules_fulfilled": true,
        "gh.branch_protection_rule.rule_suite.result": "allowed",
      }

      assert_logged(**logger_output) do
        RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)
      end
    end

    test "logs additional information about the denied rule evaluation" do
      @review_protected_branch.pull_request_reviews_enforcement_level = :non_admins
      @review_protected_branch.clear_required_status_checks
      @review_protected_branch.save!

      refname = "refs/heads/master"
      before_oid = "63611721afd41f58f801d66e543d8288b4c5eb44"
      after_oid = "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"

      ref_update = create_ref_update(@review_repo, name: refname,
        before_oid: before_oid,
        after_oid: after_oid)

      logger_output = {
        "Body": "Rule engine evaluation results",
        "gh.repo.id": @review_repo.id,
        "gh.actor.id": @review_repo.owner.id,
        "gh.actor.type": @review_repo.owner.class.name,
        "gh.branch_protection_rule.rule_suite.before_commit": before_oid,
        "gh.branch_protection_rule.rule_suite.after_commit": after_oid,
        "gh.branch_protection_rule.rule_suite.ref_name": refname,
        "gh.branch_protection_rule.rule_suite.rules_fulfilled": false,
        "gh.branch_protection_rule.rule_suite.result": "bypassed",
      }

      assert_logged(**logger_output) do
        RuleEngine::Evaluator.evaluate_rules_one(@review_repo, ref_update, @review_repo.owner)
      end
    end
  end

  test "don't apply branch protections to tags" do
    full_protection = create(:protected_branch,
      repository: @org_repo,
      creator: @org_admin,
      name: "**/*",
      pull_request_reviews_enforcement_level: :everyone)

    tag = @org_repo.tags.create("test", "63611721afd41f58f801d66e543d8288b4c5eb44", @user)

    ref_update = create_tag_update(@org_repo, name: tag.name,
                                      before_oid: tag.target_oid, after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    decision = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @org_admin)

    refute decision.rule_runs.map(&:rule_type).include?("pull_request")
    assert decision.rules_fulfilled?, "check failed: #{decision}"
    assert_nil decision.message
  end

  test "don't apply branch protections to tags with create_protected enabled" do
    full_protection = create(:protected_branch,
      repository: @org_repo,
      creator: @org_admin,
      name: "**/*",
      pull_request_reviews_enforcement_level: :everyone)
    full_protection.replace_authorized_actors(user_ids: [@org_admin.id], team_ids: [], entry_point: :test_case)
    full_protection.enable_create_protected
    full_protection.save!

    tag = @org_repo.refs.create("refs/pull/123/head", "63611721afd41f58f801d66e543d8288b4c5eb44", @user)

    ref_update = create_tag_update(@org_repo, name: tag.name,
                                      before_oid: tag.target_oid, after_oid: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24")
    decision = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @org_admin)

    refute decision.rule_runs.map(&:rule_type).include?("pull_request")
    assert decision.rules_fulfilled?, "check failed: #{decision}"
    assert_nil decision.message
  end

  test "don't apply branch protections when it is disabled on the repo" do
    full_protection = create(:protected_branch,
      repository: @org_repo,
      creator: @org_admin,
      name: "**/*",
      pull_request_reviews_enforcement_level: :everyone)

    BranchProtectionsConfig.new(@org_repo).disable_branch_protection(actor: @org_admin)

    refname = "refs/heads/master"
    before_oid = "63611721afd41f58f801d66e543d8288b4c5eb44"
    after_oid = "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"

    ref_update = create_ref_update(@org_repo, name: refname,
      before_oid: before_oid,
      after_oid: after_oid)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@org_repo, ref_update, @org_admin)

    refute decision.rule_runs.map(&:rule_type).include?("pull_request")
    assert decision.rules_fulfilled?, "check failed: #{decision}"
    assert_nil decision.message
  end

  context "ruleset-backed policies" do
    test "applies db-backed rules" do
      @repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)
      rule_configuration = create(
        :repository_rule_configuration,
        rule_type: "pull_request",
        parameters: {
          required_approving_review_count: 1,
          require_code_owner_review: false,
          dismiss_stale_reviews_on_push: false,
          ignore_approvals_from_contributors: false,
          require_last_push_approval: false,
          authorized_dismissal_actors_only: false,
          required_review_thread_resolution: false
        },
        repository_ruleset: ruleset
      )

      merge_commit = @repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

      refute_predicate decision, :rules_fulfilled?

      rule_runs = decision.rule_runs.to_a
      assert_equal 1, rule_runs.count { |run| run.rule_type == "pull_request" }
      assert_equal 1, rule_runs.count { |run| run.rule_type == "pull_request" && run.failed? }
    end

    test "doesn't apply db-backed rules that don't match conditions" do
      @repo.protected_branches.destroy_all

      ruleset = create(:repository_ruleset, source: @repo)
      rule_condition = create(
        :repository_rule_condition,
        parameters: {
          include: ["refs/heads/someotherbranch"],
          exclude: []
        },
        repository_ruleset: ruleset,
      )

      rule_configuration = create(
        :repository_rule_configuration,
        rule_type: "pull_request",
        parameters: {
          required_approving_review_count: 1,
          require_code_owner_review: false,
          dismiss_stale_reviews_on_push: false,
          ignore_approvals_from_contributors: false,
          require_last_push_approval: false,
          authorized_dismissal_actors_only: false,
          required_review_thread_resolution: false
        },
        repository_ruleset: ruleset
      )


      merge_commit = @repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first
      ref_update = create_branch_update(@repo,
        name: "master",
        before_oid: @repo.heads["master"].target_oid,
        after_oid: merge_commit.oid)

      decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @repo.owner)

      assert_predicate decision, :rules_fulfilled?

      rule_runs = decision.rule_runs.to_a
      assert_equal 0, rule_runs.count { |run| run.rule_type == "pull_request" }
    end
  end
end
