# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"
require "test_helpers/dependabot_github_app_helper"

class RuleEngineEvaluatorTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::BypassTestHelper
  include GpgKeyHelper

  fixtures do
    @biz_owner = create(:user, plan: "business_plus")
    @business = Business.first || create(:business, owners: [@biz_owner])
    @biz_org = create(:business_plus_organization, name: "biz-org", admin: @biz_owner, business: @business)
    @another_biz_org = create(:business_plus_organization, name: "biz-org-2", admin: @biz_owner, business: @business)
    @biz_org.allow_private_repository_forking(actor: @biz_org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)
    @biz_org_repo = create(:private_repository, owner: @biz_org, from_example: :simple)

    @owner = create(:user, plan: "business_plus")
    @repo_admin = create(:user, plan: "business_plus")
    @repo = create(:private_repository, owner: @owner, from_example: :simple)

    signing_key = create_gpg_key
    @user = signing_key.user

    @repo.add_member @user, action: :write

    @org_admin = create(:user)
    @org = create(:business_plus_organization, name: "org1", admin: @org_admin)
    @org.allow_private_repository_forking(actor: @org.admin, policy: Configurable::AllowPrivateRepositoryForking::EVERYWHERE)

    @org_member = create(:user)
    @org.add_member(@org_member)
    @org_repo = create(:private_repository, owner: @org, from_example: :simple)
    @org_repo.add_member(@org_member, action: :write)
    @org_repo.add_member(@org_admin, action: :admin)

    @team = create(:team, organization: @org, privacy: :closed)
    @team.add_member @org_admin
    @team.add_repository @org_repo, :admin

    @bot = create(:integration, owner: @user).bot
    make_integration_installation(integration: @bot.integration, repository: @repo, permissions: { "contents" => :write })

    ca = FakeCA.new("/CN=root1")
    @cert = ca.issue("/CN=#{@user.login}/emailAddress=#{@user.emails.verified.first.email}").freeze
    GitHub.git_signing_smime_cert_store.add_cert(ca.parsed)
    example_repo_snapshot
  end

  setup do
    Failbot.expects(:report).never

    example_repo_restore

    enable_feature_flag(:rules_engine_result_validation)

    Spokesd.enable_spokesd

    @ref_updates = [create_ref_update(@repo)]
    @org_repo_ref_updates = [create_ref_update(@org_repo)]
  end

  test "evaluates both ref and commit rules" do
    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)

    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)
    rule_runs = rule_suite.rule_runs

    assert_equal 2, rule_runs.size
    assert rule_suite.runs_by_rule_type(:deletion).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:branch_name_pattern).find(&:failed?).present?
  end

  test "evaluates max_ref_updates rules for multiple ref updates" do
    @repo.set_max_ref_updates(2, @repo.owner)

    create(:repository_ruleset, :targets_all_branches, source: @repo)
    @ref_updates << create_ref_update(@repo) << create_ref_update(@repo)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)
    rule_runs = rule_suite.rule_runs

    assert_equal 1, rule_runs.size
    assert rule_suite.runs_by_rule_type(:max_ref_updates).find(&:failed?).present?
  end

  test "skips max_ref_updates rules for a single ref update" do
    create(:repository_ruleset, :targets_all_branches, source: @repo)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)
    rule_runs = rule_suite.rule_runs

    assert_empty rule_runs
  end

  test "skips evalution for unsupported repos" do
    @repo.plan_owner.plan = "free"

    create(:repository_ruleset, :example_ruleset, source: @repo)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)
    rule_runs = rule_suite.rule_runs

    assert_equal 0, rule_runs.size
  end

  test "skips disabled rulesets" do
    create(:repository_ruleset, :example_ruleset, enforcement: :disabled, source: @repo)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)
    rule_runs = rule_suite.rule_runs

    assert_equal 0, rule_runs.size
  end

  test "skips rulesets without conditions" do
    ruleset = create(:repository_ruleset, enforcement: :disabled, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)
    rule_runs = rule_suite.rule_runs

    assert_equal 0, rule_runs.size
  end

  test "skips rulesets with non-matching conditions" do
    ruleset = create(:repository_ruleset, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset)
    create(:repository_rule_condition, repository_ruleset: ruleset, parameters: {
      include: ["refs/heads/develop"],
      exclude: []
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)
    rule_runs = rule_suite.rule_runs

    assert_equal 0, rule_runs.size
  end

  test "skips metadata pattern rules if not enterprise plan" do
    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)
    rule_runs = rule_suite.rule_runs
    assert_equal 1, rule_runs.size

    @repo.plan_owner.plan = "free"
    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)
    rule_runs = rule_suite.rule_runs
    assert_equal 0, rule_runs.size

    # pro doesn't get commit metadata rules either
    @repo.plan_owner.plan = "pro"
    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)
    rule_runs = rule_suite.rule_runs
    assert_equal 0, rule_runs.size
  end

  test "skips metadata pattern rules if not enterprise plan (org)" do
    ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@org_repo, @ref_updates, @org_repo.owner).first)
    rule_runs = rule_suite.rule_runs
    assert_equal 1, rule_runs.size

    @org_repo.plan_owner.plan = "free"
    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@org_repo, @ref_updates, @org_repo.owner).first)
    rule_runs = rule_suite.rule_runs
    assert_equal 0, rule_runs.size

    # team doesn't get commit metadata rules either
    @org_repo.plan_owner.plan = "business"
    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@org_repo, @ref_updates, @org_repo.owner).first)
    rule_runs = rule_suite.rule_runs
    assert_equal 0, rule_runs.size
  end

  test "allows admins to bypass evaluation" do
    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)

    refute rule_suite.rules_fulfilled?
    refute rule_suite.action_permitted?

    ruleset.bypass_actors << build(:repository_ruleset_bypass_actor, :repo_admin)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner).first)

    refute rule_suite.rules_fulfilled?
    assert rule_suite.action_permitted?
  end

  test "ignore non-admins when admin bypass is allowed" do
    ruleset = create(:repository_ruleset, :targets_all_branches, :repo_admin_bypass, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @user).first)

    refute rule_suite.rules_fulfilled?
    refute rule_suite.action_permitted?
  end

  test "allow bots to override push rules when explicitly added as a bypass actor" do
    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @bot).first)

    refute rule_suite.rules_fulfilled?
    refute rule_suite.action_permitted?

    bypass_actor = RepositoryRulesetBypassActor.new(
      repository_ruleset: ruleset,
      actor: @bot.integration
    )
    bypass_actor.save!

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @bot).first)

    refute rule_suite.rules_fulfilled?
    assert rule_suite.action_permitted?
  end

  test "saves rule suites to the database after evaluation" do
    ref = @repo.heads.create("test", @repo.heads["master"].target.first_parent_oid, @user)
    commit = ref.append_commit({ message: "commit", committer: @user }, @user) do |files|
      files.add "file-a", "some content"
    end

    ref_updates = [create_branch_update(@repo, name: "test", before_oid: @repo.heads["test"].target_oid, after_oid: commit.oid)]

    ruleset = create(:repository_ruleset, source: @repo)
    create(:repository_rule_condition, repository_ruleset: ruleset, parameters: { include: ["refs/heads/test"], exclude: [] })
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "required_linear_history", parameters: {})

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, ref_updates, @repo.owner).first)

    assert rule_suite.persisted?
  end

  test "ignores existing reachable commits when evaluating commit rules on branch creation" do
    commit = @repo.heads["master"].append_commit({ message: "Violating commit message", committer: @user }, @user) do |files|
      files.add "test", "Test"
    end

    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "commit_message_pattern", parameters: {
      operator: "contains",
      pattern: "GH-"
    })

    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "required_signatures")

    ref_update = create_branch_update(@repo, name: "test", before_oid: GitHub::NULL_OID, after_oid: commit.oid)

    rule_suite = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert_equal 2, rule_suite.rule_runs.size
    assert rule_suite.rules_fulfilled?
    assert rule_suite.action_permitted?
  end

  test "checks new reachable commits when evaluating commit rules on branch creation" do
    @repo.heads["master"].append_commit({ message: "Violating commit message", committer: @user }, @user) do |files|
      files.add "test1", "Test"
    end

    ref = @repo.heads.create("test", @repo.heads["master"].target.first_parent_oid, @user)
    commits = 2.times.map do |i|
      ref.append_commit({ message: "Violating commit message", committer: @user }, @user) do |files|
        files.add "test#{i + 2}", "Test"
      end
    end

    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "commit_message_pattern", parameters: {
      operator: "contains",
      pattern: "GH-"
    })

    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "required_signatures")

    ref_update = create_branch_update(@repo, name: "test", before_oid: GitHub::NULL_OID, after_oid: commits[1].oid)

    rule_suite = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert_equal 2, rule_suite.rule_runs.size
    refute rule_suite.rules_fulfilled?
    refute rule_suite.action_permitted?
    assert rule_suite.runs_by_rule_type(:commit_message_pattern).find(&:failed?).present?
    assert rule_suite.runs_by_rule_type(:required_signatures).find(&:failed?).present?
  end

  test "succeeds for new valid reachable commits when evaluating commit rules on branch creation" do
    @repo.heads["master"].append_commit({ message: "Violating commit message", committer: @user }, @user) do |files|
      files.add "test1", "Test"
    end

    ref = @repo.heads.create("test", @repo.heads["master"].target.first_parent_oid, @user)

    commits = 2.times.map do |i|
      signed_commit_oid = @cert.create_signed_commit(@repo, @user, refname: ref.name, message: "GH-0#{i + 1}: Passing commit message")
      T.must(Repositories.domain.commits.by_oid(repository: @repo, commit_oid: signed_commit_oid))
    end

    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "commit_message_pattern", parameters: {
      operator: "contains",
      pattern: "GH-"
    })

    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "required_signatures")

    ref_update = create_branch_update(@repo, name: "test", before_oid: GitHub::NULL_OID, after_oid: T.must(commits[1]).oid)

    rule_suite = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert_equal 2, rule_suite.rule_runs.size
    assert rule_suite.rules_fulfilled?
    assert rule_suite.action_permitted?
    assert rule_suite.runs_by_rule_type(:commit_message_pattern).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:required_signatures).find(&:allowed?).present?
  end

  test "checks all commits when evaluating commit rules on branch updates" do
    ref = @repo.heads.create("test", @repo.heads["master"].target.first_parent_oid, @user)
    commits = 2.times.map do |i|
      ref.append_commit({ message: "Violating commit message", committer: @user }, @user) do |files|
        files.add "test#{i}", "Test"
      end
    end

    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "commit_message_pattern", parameters: {
      operator: "contains",
      pattern: "GH-"
    })

    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "required_signatures")

    ref_update = create_branch_update(@repo, name: "test", before_oid: commits[0].oid, after_oid: commits[1].oid)

    rule_suite = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert_equal 2, rule_suite.rule_runs.size
    refute rule_suite.rules_fulfilled?
    refute rule_suite.action_permitted?
    assert rule_suite.runs_by_rule_type(:commit_message_pattern).find(&:failed?).present?
    assert rule_suite.runs_by_rule_type(:required_signatures).find(&:failed?).present?
  end

  test "can evaluate both ruleset and PB commit rules in one evaluation" do
    ref = @repo.heads.create("test", @repo.heads["master"].target.first_parent_oid, @user)
    commits = 2.times.map do |i|
      ref.append_commit({ message: "Violating commit message", committer: @user }, @user) do |files|
        files.add "test#{i}", "Test"
      end
    end

    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "commit_message_pattern", parameters: {
      operator: "contains",
      pattern: "GH-"
    })

    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "required_signatures")
    create(:protected_branch,
      name: "*",
      repository: @repo,
      creator: @user,
      signature_requirement_enforcement_level: :everyone,
      block_deletions_enforcement_level: :off,
      block_force_pushes_enforcement_level: :off
    )

    ref_update = create_branch_update(@repo, name: "test", before_oid: commits[0].oid, after_oid: commits[1].oid)

    rule_suite = RuleEngine::Evaluator.evaluate_rules_one(@repo, ref_update, @user)

    assert_equal 3, rule_suite.rule_runs.size
    refute rule_suite.rules_fulfilled?
    refute rule_suite.action_permitted?
    assert rule_suite.runs_by_rule_type(:commit_message_pattern).find(&:failed?).present?
    assert rule_suite.runs_by_rule_type(:required_signatures).all?(&:failed?)
  end

  test "always succeeds for internal refs" do
    ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)

    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    @ref_updates << create_ref_update(@repo, name: "refs/pull/1")
    @ref_updates << create_ref_update(@repo, name: "refs/__gh__/1")
    @ref_updates << create_ref_update(@repo, name: "refs/gh/queue/main")

    rule_suites = RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner)
    assert_equal 4, rule_suites.size

    branch_rule_suite = T.must(rule_suites.first)
    assert_equal 1, branch_rule_suite.rule_runs.size
    refute branch_rule_suite.rules_fulfilled?
    refute branch_rule_suite.action_permitted?
    assert branch_rule_suite.runs_by_rule_type(:branch_name_pattern).find(&:failed?).present?

    internal_ref_rule_suites = rule_suites.drop(1)
    assert_equal 1, branch_rule_suite.rule_runs.size
    assert internal_ref_rule_suites.all?(&:rules_fulfilled?)
    assert internal_ref_rule_suites.all? { |rule_suite| rule_suite.action_permitted? }
  end

  test "saves ruleset and ruleset history to rule runs" do
    enable_feature_flag(:rules_history)

    ref = @repo.heads.create("test", @repo.heads["master"].target.first_parent_oid, @user)
    commit = ref.append_commit({ message: "commit", committer: @user }, @user) do |files|
      files.add "file-a", "some content"
    end

    ref_updates = [create_branch_update(@repo, name: "test", before_oid: @repo.heads["test"].target_oid, after_oid: commit.oid)]

    ruleset = create(:repository_ruleset, source: @repo)
    create(:repository_rule_condition, repository_ruleset: ruleset, parameters: { include: ["refs/heads/test"], exclude: [] })
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "required_linear_history", parameters: {})

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, ref_updates, @repo.owner).first)

    assert rule_suite.rule_runs.all? { |run| run.rule_provider_id == ruleset.id && run.rule_provider == "ref_ruleset" }
    assert rule_suite.rule_runs.all? { |run| run.rule_history_id.present? && run.rule_history_id == ruleset.latest_history_id }
  end
  test "enterprise rulesets are inherited to the repo" do
    ruleset = create(:repository_ruleset, :with_rules, :targets_all_orgs, :targets_all_repos, :targets_all_branches, source: @business)
    ref_update = create_ref_update(@biz_org_repo)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@biz_org_repo, [ref_update], @biz_org_repo.owner).first)
    rule_runs = rule_suite.rule_runs.to_a

    if GitHub.flipper[:enterprise_rulesets].enabled?
      assert_equal 1, rule_runs.size
      assert_equal ruleset, rule_runs.first&.source_ruleset
    else
      assert_equal 0, rule_runs.size
    end
  end

  test "enterprise rulesets are inherited to the repo via org id condition" do
    ruleset = create(:repository_ruleset, :with_rules, :targets_org, :targets_all_repos, :targets_all_branches, org: @biz_org, source: @business)
    ref_update = create_ref_update(@biz_org_repo)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@biz_org_repo, [ref_update], @biz_org_repo.owner).first)
    rule_runs = rule_suite.rule_runs.to_a

    if GitHub.flipper[:enterprise_rulesets].enabled?
      assert_equal 1, rule_runs.size
      assert_equal ruleset, rule_runs.first&.source_ruleset
    else
      assert_equal 0, rule_runs.size
    end
  end

end
