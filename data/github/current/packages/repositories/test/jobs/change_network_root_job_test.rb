# typed: true
# frozen_string_literal: true

require "test_helper"

class ChangeNetworkRootJobTest < GitHub::TestCase
  fixtures do
    @biz = Business.first || create(:business)
    @org = create(:organization, business: @biz, plan: "business_plus")
    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    @org2 = create(:organization,  business: @biz, plan: "business_plus")
    @org2.allow_private_repository_forking(actor: @org2.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @repo = create(:repository, owner: @org, internal: true)
    @bob = create(:user)
    @org.add_member(@bob, action: :admin)

    @org2_fork = create(:fork_repository, forker: @org2.admin, organization: @org2, fork_repo: @repo)
    @fork = create(:fork_repository, forker: @bob, fork_repo: @repo)
    @network = @repo.network
  end

  test "doesn't do anything if the repository doesn't exist" do
    refute ChangeNetworkRootJob.perform_now(-1)
  end

  test "makes a repository the root of its network" do
    assert @fork.fork?
    assert @repo.network_root?

    ChangeNetworkRootJob.perform_now(@fork.id)

    assert @repo.reload.fork?
    assert @fork.reload.network_root?
  end

  test "makes a repository the root of its network when the old root is nil" do
    assert @fork.fork?
    @repo.delete # delete without callbacks to force broken network
    assert_nil @network.reload.root
    assert @network.root_id

    ChangeNetworkRootJob.perform_now(@fork.id)

    assert @fork.reload.network_root?
  end

  test "copies push rules to the new network root" do
    push_ruleset = build(:repository_ruleset, target: "push", source: @repo)
    push_rule = build(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    push_ruleset.save!
    push_rule.save!

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    push_rules = RepositoryRuleset.load_for(source: @repo, include_parents: false, targets: %w[push branch])
    assert_equal 2, push_rules.size

    push_rules = RepositoryRuleset.load_for(source: @fork, include_parents: false, targets: %w[push branch])
    assert_equal 0, push_rules.size

    # change the root to the org2 fork
    ChangeNetworkRootJob.perform_now(@org2_fork.id)

    # assert the fork is now the root
    assert @repo.reload.fork?
    assert @org2_fork.reload.network_root?

    # assert the push rule was copied to the fork
    push_rules = RepositoryRuleset.load_for(source: @org2_fork, include_parents: false, targets: %w[push branch])
    assert_equal 1, push_rules.size
    rule = T.must(push_rules.first)
    assert_equal "push", rule.target
    assert_equal "max_file_path_length", rule.rule_configurations[0].rule_type

    # assert the push rule on the old root was deleted
    push_rules = RepositoryRuleset.load_for(source: @repo, include_parents: false, targets: %w[push branch])
    assert_equal 1, push_rules.size
    rule = T.must(push_rules.first)
    assert_equal "branch", rule.target

    # now make the user fork the root. This should not copy the push rule
    ChangeNetworkRootJob.perform_now(@fork.id)

    # assert the fork is now the root
    assert @repo.reload.fork?
    assert @fork.reload.network_root?

    push_rules = RepositoryRuleset.load_for(source: @fork, include_parents: false, targets: %w[push branch])

    if @fork.plan_supports?(:enterprise_rulesets)
      assert_equal 1, push_rules.size

      push_rules = RepositoryRuleset.load_for(source: @org2_fork, include_parents: false, targets: %w[push branch])
      assert_equal 0, push_rules.size
    else
      # assert the push rule was not copied to the fork
      assert_equal 0, push_rules.size

      # assert the push rule on the org root was not deleted
      push_rules = RepositoryRuleset.load_for(source: @org2_fork, include_parents: false, targets: %w[push branch])
      assert_equal 1, push_rules.size
      rule = T.must(push_rules.first)
      assert_equal "push", rule.target
    end
  end
end
