# typed: true
# frozen_string_literal: true

require "test_helper"

# We need the exact same tests for both users and orgs.
# Below, we create two test suites, one for users and
# one for orgs, and include this module in both.
module SharedRepositoryRefProtectionTests
  extend T::Helpers
  include RulesEngine::RefUpdateTestHelper

  requires_ancestor { GitHub::TestCase }

  def test_ref_protected
    assert_equal false, @repo.refs["master"].protected?

    @repo.protected_branches.create!(name: "master", creator: @admin)
    assert_equal true, @repo.refs["master"].protected?
  end

  def test_can_update_ref_returns_instance_of_rule_engine_evaluation_result
    rule_suite = RuleEngine::Evaluator.evaluate_rules_one(@repo, @ref_update, @admin)

    assert_instance_of RuleEngine::RuleSuite, rule_suite
  end

  def test_can_update_ref_without_branch_protection
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, @ref_update, @admin)

    assert decision.action_permitted?, "check failed: #{decision}"
    assert_nil decision.message
  end

  def test_can_update_ref_with_branch_protection
    @repo.protected_branches.create! name: "master", creator: @admin

    before = @repo.heads["master"].target_oid
    after = @repo.commits.create({ message: "New commit", committer: @admin }, before) do |files|
      files.add "Newer file", "New file"
    end.oid

    ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: after)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @admin)

    assert decision.action_permitted?, "check failed: #{decision}"
    assert_nil decision.message
  end

  def test_cannot_delete_ref_with_branch_protection
    @repo.protected_branches.create! name: "master", creator: @admin

    before = @repo.heads["master"].target_oid
    ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: GitHub::NULL_OID)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @write_user)

    refute decision.action_permitted?
  end

  def test_admins_cannot_delete_ref_with_branch_protection_when_enforced_for_admins
    assert @repo.adminable_by?(@admin)
    @repo.protected_branches.create! name: "master", creator: @admin, required_status_checks_enforcement_level: :everyone

    before = @repo.heads["master"].target_oid
    ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: GitHub::NULL_OID)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @admin)

    refute decision.action_permitted?, "check passed: #{decision}"
    assert_equal "Cannot delete this #{ref_update.ref_type != "unknown" ? ref_update.ref_type : 'ref'}", decision.message
  end

  def test_admins_cannot_delete_ref_with_branch_protection_when_not_enforced_for_admins
    assert @repo.adminable_by?(@admin)
    @repo.protected_branches.create! name: "master", creator: @admin, required_status_checks_enforcement_level: :everyone

    before = @repo.heads["master"].target_oid
    ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: GitHub::NULL_OID)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @admin)

    refute decision.action_permitted?, "check passed: #{decision}"
    assert_equal "Cannot delete this #{ref_update.ref_type != "unknown" ? ref_update.ref_type : 'ref'}", decision.message
  end

  def test_cannot_non_fast_forward_ref_with_branch_protection
    @repo.protected_branches.create! name: "master", creator: @admin

    before = @repo.heads["master"].target_oid
    after = @repo.heads["master"].target.parent_oids.first
    ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: after)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @write_user)

    refute decision.action_permitted?
  end

  def test_admins_cannot_non_fast_forward_ref_with_branch_protection_when_enforced_for_admins
    assert @repo.adminable_by?(@admin)
    @repo.protected_branches.create! name: "master", creator: @admin, required_status_checks_enforcement_level: :everyone

    before = @repo.heads["master"].target_oid
    after = @repo.heads["master"].target.parent_oids.first
    ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: after)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @admin)

    refute decision.action_permitted?
  end

  def test_admins_cannot_non_fast_forward_ref_with_branch_protection_when_not_enforced_for_admins
    assert @repo.adminable_by?(@admin)
    @repo.protected_branches.create! name: "master", creator: @admin

    before = @repo.heads["master"].target_oid
    after = @repo.heads["master"].target.parent_oids.first
    ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: after)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @admin)

    refute decision.action_permitted?, "check passed: #{decision}"
    assert_equal "Cannot force-push to this #{ref_update.ref_type != "unknown" ? ref_update.ref_type : 'ref'}", decision.message
  end

  def test_can_update_ref_with_branch_protection_status
    prot_branch = @repo.protected_branches.create! name: "master", creator: @admin, required_status_checks_enforcement_level: :non_admins
    prot_branch.replace_status_contexts %w(default)

    before = @repo.heads["master"].target_oid
    after = @repo.commits.create({ message: "New commit", committer: @admin }, before) do |files|
      files.add "Newer file", "New file"
    end.oid

    ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: after)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @write_user)

    refute decision.action_permitted?, "check passed: #{decision}"
    assert_equal "Required status check \"default\" is expected.", decision.message

    create :status, repository: @repo, creator: @admin, sha: after, context: "default", state: "success"

    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @write_user)

    assert decision.action_permitted?, "check failed: #{decision}"
    assert_nil decision.message
  end

  def test_admins_can_override_ref_with_branch_protection_status
    prot_branch = @repo.protected_branches.create! name: "master", creator: @admin
    prot_branch.replace_status_contexts %w(default)

    before = @repo.heads["master"].target_oid
    after = @repo.commits.create({ message: "New commit", committer: @admin }, before) do |files|
      files.add "Newer file", "New file"
    end.oid

    ref_update = create_branch_update(@repo, name: "master", before_oid: before, after_oid: after)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @admin)

    assert decision.action_permitted?, "check passed: #{decision}"

    # when required_status_checks_enforcement_level is :everyone, admins cannot override
    prot_branch.required_status_checks_enforcement_level = :everyone
    prot_branch.save!

    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @admin)

    refute decision.action_permitted?, "check passed: #{decision}"
    assert_equal "Required status check \"default\" is expected.", decision.message
  end

  def test_can_delete_tag_with_same_name_as_protected_branch
    @repo.protected_branches.create! name: "master", creator: @admin
    @repo.tags.create("master", @repo.heads["master"].sha, @admin)

    ref_update = create_tag_update(@repo, name: "master", before_oid: @repo.heads["master"].sha, after_oid: GitHub::NULL_OID)
    decision = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @admin)

    assert decision.action_permitted?, "check failed: #{decision}"
  end

  def test_cannot_update_ref_without_an_author
    assert_raises TypeError do
      RuleEngine::Evaluator.evaluate_rules_one(@repo, @ref_update, T.cast(nil, T.untyped))
    end
  end

  def test_cannot_update_ref_with_an_author_hash
    assert_raises TypeError do
      RuleEngine::Evaluator.evaluate_rules_one(@repo, @ref_update, T.cast({ name: "Foo", email: "foo@example.com" }, T.untyped))
    end
  end

  def test_nonexistent_user_cannot_commit_to_branch
    refute @repo.can_commit_to_branch?(nil, "master")
  end

  def test_users_can_commit_to_non_protected_branch
    assert @repo.can_commit_to_branch?(@admin, "master")
  end

  def test_users_cannot_commit_to_protected_branch
    protected_branch = @repo.protect_branch("master", creator: @admin, entry_point: :test_case)
    protected_branch.pull_request_reviews_enforcement_level = :everyone
    protected_branch.save
    refute @repo.can_commit_to_branch?(@admin, "master")
  end

  if GitHub.merge_queues_enabled?
    def test_users_cannot_commit_to_merge_queue_locked_branch
      MergeQueueLockedRef.create!(
        repository: @repo_with_merge_queue,
        queue: @repo_with_merge_queue.default_merge_queue,
        ref: "lazy_delegator",
      )

      refute @repo_with_merge_queue.can_commit_to_branch?(@admin, "lazy_delegator")
    end

    def test_users_can_commit_to_branch_that_is_not_merge_queue_locked
      MergeQueueLockedRef.create!(
        repository: @repo_with_merge_queue,
        queue: @repo_with_merge_queue.default_merge_queue,
        ref: "lazy_delegator",
      )

      assert @repo_with_merge_queue.can_commit_to_branch?(@admin, "master")
    end

    def test_users_can_commit_to_merge_queue_locked_branch_if_repo_has_merge_queue_access
      Repository.any_instance.stubs(:merge_queue_enabled?).returns(false)

      MergeQueueLockedRef.create!(
        repository: @repo_with_merge_queue,
        queue: @repo_with_merge_queue.default_merge_queue,
        ref: "lazy_delegator",
      )

      assert @repo_with_merge_queue.can_commit_to_branch?(@admin, "lazy_delegator")
    end
  else
    def test_users_can_commit_to_merge_queue_locked_branch
      MergeQueueLockedRef.create!(
        repository: @repo_with_merge_queue,
        queue: @repo_with_merge_queue.default_merge_queue,
        ref: "lazy_delegator",
      )

      assert @repo_with_merge_queue.can_commit_to_branch?(@admin, "lazy_delegator")
    end
  end
end

class RepositoryRefProtectionProtectedBranchesEnabledForTheOrgTest < GitHub::TestCase
  include SharedRepositoryRefProtectionTests
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @admin = create(:user, plan: "medium")
    @org = create(:organization, plan: "silver").tap { |o| o.add_member(@admin, action: :admin) }
    @owner = @org

    @write_user = create(:user)

    @repo = create(:private_repository, owner: @org, from_example: :mojombo_grit)
    @repo.add_member(@write_user, @admin, event = false, action: :write)

    @repo_with_merge_queue = create(:repository, :has_merge_queue, owner: @admin)

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    oid = @repo.heads["master"].target_oid
    @ref_update = create_branch_update(@repo, name: "master", before_oid: oid, after_oid: oid)
  end
end

class RepositoryRefProtectionProtectedBranchesEnabledForTheUserTest < GitHub::TestCase
  include SharedRepositoryRefProtectionTests
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @admin = create(:user, plan: "medium")
    @owner = @admin

    @write_user = create(:user)

    @repo = create(:private_repository, owner: @admin, from_example: :mojombo_grit)
    @repo.add_member(@write_user, @admin, event = false, action: :write)
    @repo_with_merge_queue = create(:repository, :has_merge_queue, owner: @admin)

    example_repo_snapshot
  end

  setup do
    example_repo_restore

    oid = @repo.heads["master"].target_oid
    @ref_update = create_branch_update(@repo, name: "master", before_oid: oid, after_oid: oid)
  end
end
