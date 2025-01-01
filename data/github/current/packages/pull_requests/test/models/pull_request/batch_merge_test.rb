# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestBatchMergeTest < GitHub::TestCase
  fixtures do
    @actor = create(:user)
    @org = create(:organization, admin: @actor)
    @upstream_repo = create(:repository, owner: @org, from_example: :pull_request_fork)

    @advisory = create(:repository_advisory, repository: @upstream_repo, author: @actor)

    only = [RepositoryCloneJob]
    @workspace_repo = perform_enqueued_jobs(only: only) do
      GitHub.context.push(actor_id: @actor.id)
      RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @actor).tap(&:save!).tap(&:reload)
    end

    example_repo_snapshot
  end

  setup do
    Spokesd.enable_spokesd

    WebFlowHelper.setup_webflow
    example_repo_restore

    ref = @workspace_repo.heads.create("fix-1", @workspace_repo.heads.find("master").target, @actor)
    metadata = { message: "this is fix 1", committer: @actor }
    @commit1 = ref.append_commit(metadata, @actor) do |files|
      files.add("README.md", "change")
    end

    ref = @workspace_repo.heads.create("fix-2", @workspace_repo.heads.find("topic").target, @actor)
    metadata = { message: "this is fix 2", committer: @actor }
    @commit2 = ref.append_commit(metadata, @actor) do |files|
      files.add("README.md", "change")
    end

    @pull_request1 = PullRequest.new(
      repository:      @workspace_repo,
      base_repository: @upstream_repo,
      base_user:       @upstream_repo.owner,
      base_ref:        "master",
      head_repository: @workspace_repo,
      head_user:       @workspace_repo.owner,
      head_ref:        "fix-1",
      issue:           create(:issue, user: @actor, repository: @workspace_repo),
      user:            @actor,
    )
    assert_predicate @pull_request1, :valid?

    @pull_request2 = PullRequest.new(
      repository:      @workspace_repo,
      base_repository: @upstream_repo,
      base_user:       @upstream_repo.owner,
      base_ref:        "topic",
      head_repository: @workspace_repo,
      head_user:       @workspace_repo.owner,
      head_ref:        "fix-2",
      issue:           create(:issue, user: @actor, repository: @workspace_repo),
      user:            @actor,
    )
    assert_predicate @pull_request2, :valid?
  end

  def create_merge_conflict_on_pull_request2
    @upstream_repo.refs.find("topic").append_commit({
      message: "Commit on topic",
      committer: @actor,
    }, @actor) do |files|
      files.add("README.md", "Will this conflict?")
    end

    @workspace_repo.refs.find("fix-2").append_commit({
      message: "Commit on fix-2",
      committer: @actor,
    }, @actor) do |files|
      files.add("README.md", "This will conflict")
    end

    @pull_request2.reload
  end

  test "Fails for nil repo" do
    batch_merge = PullRequest::BatchMerge.new(nil, [@pull_request1], @actor)

    assert_raises(ActiveModel::ValidationError) do
      batch_merge.perform
    end
  end

  test "Fails for empty pull request list" do
    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [], @actor)

    assert_raises(ActiveModel::ValidationError) do
      batch_merge.perform
    end
  end

  test "Fails if a PR is in the base repository" do
    batch_merge = PullRequest::BatchMerge.new(@workspace_repo, [@pull_request1], @actor)

    assert_raises(ActiveModel::ValidationError) do
      batch_merge.perform
    end
  end

  test "Fails if PRs are not all from the same repo" do
    @pull_request1.save!
    assert_predicate @pull_request1, :persisted?

    ref = @upstream_repo.heads.create("fix-2", @workspace_repo.heads.find("topic").target, @actor)
    metadata = { message: "this is fix 2", committer: @actor }
    ref.append_commit(metadata, @actor) do |files|
      files.add("README.md", "change")
    end

    pr2 = PullRequest.new(
      repository:      @upstream_repo,
      base_repository: @upstream_repo,
      base_user:       @upstream_repo.owner,
      base_ref:        "topic",
      head_repository: @upstream_repo,
      head_user:       @upstream_repo.owner,
      head_ref:        "fix-2",
      issue:           create(:issue, user: @actor, repository: @upstream_repo),
      user:            @actor,
    )
    pr2.save!

    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request1, pr2], @actor)

    assert_raises(ActiveModel::ValidationError) do
      batch_merge.perform
    end
  end

  test "Fails if multiple PRs target the same ref" do
    @pull_request1.save!
    assert_predicate @pull_request1, :persisted?
    @pull_request2.save!
    assert_predicate @pull_request2, :persisted?

    ref = @workspace_repo.heads.create("fix-3", @workspace_repo.heads.find("master").target, @actor)
    metadata = { message: "this is fix 3", committer: @actor }
    @commit2 = ref.append_commit(metadata, @actor) do |files|
      files.add("README.md", "change")
    end

    pr3 = PullRequest.new(
      repository:      @workspace_repo,
      base_repository: @upstream_repo,
      base_user:       @upstream_repo.owner,
      base_ref:        "topic",
      head_repository: @workspace_repo,
      head_user:       @workspace_repo.owner,
      head_ref:        "fix-3",
      issue:           create(:issue, user: @actor, repository: @workspace_repo),
      user:            @actor,
    )
    pr3.save!

    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request1, @pull_request2, pr3], @actor)

    assert_raises(ActiveModel::ValidationError) do
      batch_merge.perform
    end
  end

  test "accounts for upstream base ref updates in merge" do
    GitHub.flipper[:disable_xnetwork_fetch].disable
    @pull_request2.save!
    assert_predicate @pull_request2, :persisted?

    refute @upstream_repo.rpc.object_exists?(@commit2.oid, "commit")

    @upstream_repo.refs.find("topic").append_commit({
      message: "Commit on topic",
      committer: @actor,
    }, @actor) do |files|
      files.add("new-file.md", "change")
    end
    @pull_request2.reload

    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request2], @actor)
    batch_success, batch_merge_result = batch_merge.perform
    assert batch_success
    assert_equal 1, batch_merge_result.length

    batch_merge_result.each_value do |result|
      assert GitRPC::Util.valid_refname?(result.base_ref)
      assert GitRPC::Util.valid_full_oid?(result.base_sha)
      assert GitRPC::Util.valid_full_oid?(result.new_sha)
      assert @upstream_repo.rpc.commit_visible?(result.new_sha)
    end

    assert_predicate @pull_request2, :merged?
    assert_predicate @pull_request2, :closed?

    assert @upstream_repo.rpc.commit_visible?(@commit2.oid)
  end

  test "Successfully merges multiple PRs" do
    @pull_request1.save!
    assert_predicate @pull_request1, :persisted?
    @pull_request2.save!
    assert_predicate @pull_request2, :persisted?

    refute @upstream_repo.rpc.object_exists?(@commit1.oid, "commit")
    refute @upstream_repo.rpc.object_exists?(@commit2.oid, "commit")

    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request1, @pull_request2], @actor)
    batch_success, batch_merge_result = batch_merge.perform
    assert batch_success
    assert_equal 2, batch_merge_result.length

    batch_merge_result.each_value do |result|
      assert GitRPC::Util.valid_refname?(result.base_ref)
      assert GitRPC::Util.valid_full_oid?(result.base_sha)
      assert GitRPC::Util.valid_full_oid?(result.new_sha)
      assert @upstream_repo.rpc.commit_visible?(result.new_sha)
    end

    assert_predicate @pull_request1, :merged?
    assert_predicate @pull_request1, :closed?
    assert_predicate @pull_request2, :merged?
    assert_predicate @pull_request2, :closed?

    assert @upstream_repo.rpc.commit_visible?(@commit1.oid)
    assert @upstream_repo.rpc.commit_visible?(@commit2.oid)
  end

  test "Fails on merge conflict" do
    @pull_request1.save!
    assert_predicate @pull_request1, :persisted?
    @pull_request2.save!
    assert_predicate @pull_request2, :persisted?

    refute @upstream_repo.rpc.object_exists?(@commit1.oid, "commit")
    refute @upstream_repo.rpc.object_exists?(@commit2.oid, "commit")

    create_merge_conflict_on_pull_request2

    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request1, @pull_request2], @actor)
    batch_success, batch_merge_result = batch_merge.perform
    refute batch_success
    assert_equal 1, batch_merge_result.length

    result = batch_merge_result[@pull_request2]
    refute_predicate result.fail_message, :nil?
    assert_equal :not_mergeable, result.fail_code

    refute_predicate @pull_request1, :merged?
    refute_predicate @pull_request1, :closed?
    refute_predicate @pull_request2, :merged?
    refute_predicate @pull_request2, :closed?

    refute @upstream_repo.rpc.object_exists?(@commit1.oid)
    refute @upstream_repo.rpc.object_exists?(@commit2.oid)
  end

  test "Fails when branch requires signatures" do
    GitHub.flipper[:security_advisory_rule_evaluation].disable
    GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)

    @pull_request1.save!
    assert_predicate @pull_request1, :persisted?
    @pull_request2.save!
    assert_predicate @pull_request2, :persisted?

    refute @upstream_repo.rpc.object_exists?(@commit2.oid, "commit")

    create(:protected_branch,
      repository: @upstream_repo,
      name: "topic",
      required_status_checks_enforcement_level: :off,
      pull_request_reviews_enforcement_level: :off,
      signature_requirement_enforcement_level: :everyone,
    )

    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request1, @pull_request2], @actor)
    batch_success, batch_merge_result = batch_merge.perform
    refute batch_success
    assert_equal 1, batch_merge_result.length
    result = batch_merge_result[@pull_request2]
    assert_match /branch requires that commits be signed/, result.fail_message
    assert_equal :protected_branch, result.fail_code

    refute_predicate @pull_request1, :merged?
    refute_predicate @pull_request1, :closed?
    refute_predicate @pull_request2, :merged?
    refute_predicate @pull_request2, :closed?

    refute @upstream_repo.rpc.object_exists?(@commit1.oid)
    refute @upstream_repo.rpc.object_exists?(@commit2.oid)
  end

  test "Succeeds when protected branch policy can be bypassed" do
    GitHub.flipper[:security_advisory_rule_evaluation_opt_out].disable
    GitHub.flipper[:security_advisory_rule_evaluation].enable
    GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)

    @pull_request1.save!
    assert_predicate @pull_request1, :persisted?
    @pull_request2.save!
    assert_predicate @pull_request2, :persisted?

    refute @upstream_repo.rpc.object_exists?(@commit2.oid, "commit")

    create(:protected_branch,
      repository: @upstream_repo,
      name: "topic",
      required_status_checks_enforcement_level: :off,
      pull_request_reviews_enforcement_level: :non_admins,
      required_approving_review_count: 1,
    )

    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request1, @pull_request2], @actor)
    batch_success, batch_merge_result = batch_merge.perform
    assert batch_success
    assert_equal 2, batch_merge_result.length

    batch_merge_result.each_value do |result|
      assert GitRPC::Util.valid_refname?(result.base_ref)
      assert GitRPC::Util.valid_full_oid?(result.base_sha)
      assert GitRPC::Util.valid_full_oid?(result.new_sha)
      assert @upstream_repo.rpc.commit_visible?(result.new_sha)
    end

    assert_predicate @pull_request1, :merged?
    assert_predicate @pull_request1, :closed?
    assert_predicate @pull_request2, :merged?
    assert_predicate @pull_request2, :closed?

    assert @upstream_repo.rpc.commit_visible?(@commit1.oid)
    assert @upstream_repo.rpc.commit_visible?(@commit2.oid)

    # Suites only produced in a ruleset was included in the evaluation
    assert RuleEngine::RuleSuite.all.empty?
  end

  test "Fails when protected branch policy violated" do
    GitHub.flipper[:security_advisory_rule_evaluation_opt_out].disable
    GitHub.flipper[:security_advisory_rule_evaluation].enable
    GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)

    @pull_request1.save!
    assert_predicate @pull_request1, :persisted?
    @pull_request2.save!
    assert_predicate @pull_request2, :persisted?

    refute @upstream_repo.rpc.object_exists?(@commit2.oid, "commit")

    create(:protected_branch,
      repository: @upstream_repo,
      name: "topic",
      required_status_checks_enforcement_level: :off,
      pull_request_reviews_enforcement_level: :everyone,
      required_approving_review_count: 1,
    )

    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request1, @pull_request2], @actor)
    batch_success, batch_merge_result = batch_merge.perform
    refute batch_success
    assert_equal 1, batch_merge_result.length
    result = batch_merge_result[@pull_request2]
    assert_match /rule violations found/, result.fail_message
    assert_equal :repository_rule_violation, result.fail_code

    refute_predicate @pull_request1, :merged?
    refute_predicate @pull_request1, :closed?
    refute_predicate @pull_request2, :merged?
    refute_predicate @pull_request2, :closed?

    assert RuleEngine::RuleSuite.all.empty?
  end

  test "Succeeds when ruleset can be bypassed" do
    GitHub.flipper[:security_advisory_rule_evaluation_opt_out].disable
    GitHub.flipper[:security_advisory_rule_evaluation].enable
    GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)

    @pull_request1.save!
    assert_predicate @pull_request1, :persisted?
    @pull_request2.save!
    assert_predicate @pull_request2, :persisted?

    refute @upstream_repo.rpc.object_exists?(@commit2.oid, "commit")

    ruleset = create(:repository_ruleset,
      :targets_branch,
      :repo_admin_bypass,
      source: @upstream_repo,
      qualified_ref_name: "refs/heads/topic",
    )

    create(:repository_rule_configuration,
      :required_status_checks,
      repository_ruleset: ruleset
    )

    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request1, @pull_request2], @actor)
    batch_success, batch_merge_result = batch_merge.perform
    assert batch_success
    assert_equal 2, batch_merge_result.length

    batch_merge_result.each_value do |result|
      assert GitRPC::Util.valid_refname?(result.base_ref)
      assert GitRPC::Util.valid_full_oid?(result.base_sha)
      assert GitRPC::Util.valid_full_oid?(result.new_sha)
      assert @upstream_repo.rpc.commit_visible?(result.new_sha)
    end

    assert_predicate @pull_request1, :merged?
    assert_predicate @pull_request1, :closed?
    assert_predicate @pull_request2, :merged?
    assert_predicate @pull_request2, :closed?

    assert @upstream_repo.rpc.commit_visible?(@commit1.oid)
    assert @upstream_repo.rpc.commit_visible?(@commit2.oid)

    assert_equal 1, RuleEngine::RuleSuite.count
    assert_equal "refs/heads/topic", T.must(RuleEngine::RuleSuite.first).ref_name
  end

  test "Fails when ruleset is violated" do
    GitHub.flipper[:security_advisory_rule_evaluation_opt_out].disable
    GitHub.flipper[:security_advisory_rule_evaluation].enable
    GitHub.gpg.stubs(:sign).raises(GpgVerify::EarthsmokeError)

    @pull_request1.save!
    assert_predicate @pull_request1, :persisted?
    @pull_request2.save!
    assert_predicate @pull_request2, :persisted?

    refute @upstream_repo.rpc.object_exists?(@commit2.oid, "commit")

    ruleset = create(:repository_ruleset,
      :targets_branch,
      source: @upstream_repo,
      qualified_ref_name: "refs/heads/topic",
    )

    create(:repository_rule_configuration,
      :required_status_checks,
      repository_ruleset: ruleset
    )

    batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request1, @pull_request2], @actor)
    batch_success, batch_merge_result = batch_merge.perform
    refute batch_success
    assert_equal 1, batch_merge_result.length
    result = batch_merge_result[@pull_request2]
    assert_match /bypass branch protections can merge/, result.fail_message
    assert_equal :repository_rule_violation, result.fail_code

    refute_predicate @pull_request1, :merged?
    refute_predicate @pull_request1, :closed?
    refute_predicate @pull_request2, :merged?
    refute_predicate @pull_request2, :closed?

    refute @upstream_repo.rpc.object_exists?(@commit1.oid)
    refute @upstream_repo.rpc.object_exists?(@commit2.oid)

    assert RuleEngine::RuleSuite.all.empty?
  end

  context "#valid?" do
    test "returns true when valid" do
      batch_merge = PullRequest::BatchMerge.new(@upstream_repo, [@pull_request1], @actor)

      assert_equal true, batch_merge.valid?
      assert batch_merge.errors.empty?
    end

    test "returns false and sets errors when invalid" do
      batch_merge = PullRequest::BatchMerge.new(@workspace_repo, [@pull_request1], @actor)

      assert_equal false, batch_merge.valid?
      assert_equal(
        {
          base: [
            {
              error: :invalid_base_repository,
            },
          ],
        },
        batch_merge.errors.details,
      )
    end
  end
end
