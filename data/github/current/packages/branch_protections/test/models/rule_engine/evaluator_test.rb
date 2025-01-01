# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"
require "test_helpers/dependabot_github_app_helper"

class RuleEngineEvaluatorTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::BypassTestHelper
  include GpgKeyHelper

  Spokesd.share_spokesdb(self)

  fixtures do
    @biz_owner = create(:user, plan: "business_plus")
    @business = Business.first || create(:business, owners: [@biz_owner])
    @biz_org = create(:business_plus_organization, name: "biz-org", admin: @biz_owner, business: @business)
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

    GitHub.flipper[:rules_engine_result_validation].enable

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

  test "skips evaluating push targeting rules during pre-receive phase when FF is disabled" do
    GitHub.flipper[:push_rulesets].disable

    push_ruleset = build(:repository_ruleset, target: "push", source: @repo)
    push_rule = build(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    push_ruleset.save!(validate: false)
    push_rule.save!(validate: false)

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@repo, @ref_updates, @repo.owner, phase: RuleEngine::Types::Phase::PreReceive).first)

    assert_empty rule_suite.rule_runs
  end

  test "evaluates push targeting rules during pre-receive phase" do
    GitHub.flipper[:push_rulesets].enable

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@org_repo, @org_repo_ref_updates, @org_repo.owner, phase: RuleEngine::Types::Phase::PreReceive).first)
    rule_runs = rule_suite.rule_runs

    assert_equal 1, rule_runs.size
    assert rule_suite.runs_by_rule_type(:max_file_path_length).find(&:allowed?).present?
  end

  test "skips evaluation of rules with skip_evaluation? during pre-receive phase" do
    GitHub.flipper[:push_rulesets].enable
    RuleEngine::Rules::MaxFileSizeRule.any_instance.stubs(:skip_evaluation?).returns(true)

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_size", parameters: {
      max_file_size: 1
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@org_repo, @org_repo_ref_updates, @org_repo.owner, phase: RuleEngine::Types::Phase::PreReceive).first)
    rule_runs = rule_suite.rule_runs

    assert_equal 1, rule_runs.size
    assert rule_suite.runs_by_rule_type(:max_file_path_length).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:max_file_size).empty?
  end

  test "evaluates ref targeting rules during post-receive phase" do
    GitHub.flipper[:push_rulesets].enable

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(
      @org_repo,
      @org_repo_ref_updates,
      @org_repo.owner,
      phase: RuleEngine::Types::Phase::PostReceive,
      options: {
        pre_receive_rule_suites: []
      }).first)

    rule_runs = rule_suite.rule_runs

    assert_equal 2, rule_runs.size
    assert rule_suite.runs_by_rule_type(:deletion).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:branch_name_pattern).find(&:failed?).present?
  end

  test "skips evaluation of rules with skip_evaluation? during post-receive phase" do
    GitHub.flipper[:push_rulesets].enable
    RuleEngine::Rules::BranchNamePatternRule.any_instance.stubs(:skip_evaluation?).returns(true)

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(
      @org_repo,
      @org_repo_ref_updates,
      @org_repo.owner,
      phase: RuleEngine::Types::Phase::PostReceive,
      options: {
        pre_receive_rule_suites: []
      }).first)

    rule_runs = rule_suite.rule_runs

    assert_equal 1, rule_runs.size
    assert rule_suite.runs_by_rule_type(:deletion).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:branch_name_pattern).empty?
  end

  test "evaluates ref targeting rules by default when phase is not specified" do
    GitHub.flipper[:push_rulesets].enable

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(
      @org_repo,
      @org_repo_ref_updates,
      @org_repo.owner,
      options: {
        pre_receive_rule_suites: []
      }).first)

    rule_runs = rule_suite.rule_runs

    assert_equal 2, rule_runs.size
    assert rule_suite.runs_by_rule_type(:deletion).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:branch_name_pattern).find(&:failed?).present?
  end

  test "evaluates all rules ignoring targeting when phase is nil" do
    GitHub.flipper[:push_rulesets].enable

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(@org_repo, @org_repo_ref_updates, @org_repo.owner, phase: nil).first)
    rule_runs = rule_suite.rule_runs

    assert_equal 3, rule_runs.size
    assert rule_suite.runs_by_rule_type(:deletion).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:max_file_path_length).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:branch_name_pattern).find(&:failed?).present?
  end

  test "merges pre-receive and post-receive rule suites" do
    GitHub.flipper[:push_rulesets].enable

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    pre_receive_rule_suites = RuleEngine::Evaluator.evaluate_rules(@org_repo, @org_repo_ref_updates, @org_repo.owner, phase: RuleEngine::Types::Phase::PreReceive)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(
      @org_repo,
      @org_repo_ref_updates,
      @org_repo.owner,
      phase: RuleEngine::Types::Phase::PostReceive,
      options: {
        pre_receive_rule_suites:,
      }).first)

    rule_runs = rule_suite.rule_runs

    assert_equal 3, rule_runs.size
    assert_equal T.must(pre_receive_rule_suites.first).id, rule_suite.id
    assert rule_suite.runs_by_rule_type(:deletion).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:max_file_path_length).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:branch_name_pattern).find(&:failed?).present?
  end

  test "merging pre-receive and post-receive rule suites allows different actors" do
    GitHub.flipper[:push_rulesets].enable

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    pre_receive_rule_suites = RuleEngine::Evaluator.evaluate_rules(@org_repo, @org_repo_ref_updates, @user, phase: RuleEngine::Types::Phase::PreReceive)

    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(
      @org_repo,
      @org_repo_ref_updates,
      @org_repo.owner,
      phase: RuleEngine::Types::Phase::PostReceive,
      options: {
        pre_receive_rule_suites:,
      }).first)

    rule_runs = rule_suite.rule_runs

    assert_equal 3, rule_runs.size
    assert_equal T.must(pre_receive_rule_suites.first).id, rule_suite.id
    assert rule_suite.runs_by_rule_type(:deletion).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:max_file_path_length).find(&:allowed?).present?
    assert rule_suite.runs_by_rule_type(:branch_name_pattern).find(&:failed?).present?
    assert @org_repo.owner, rule_suite.actor
  end

  test "evaluates pre-commit rules" do
    GitHub.flipper[:push_rulesets].enable

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(
      @org_repo,
      nil,
      @org_repo.owner,
      {
        message: nil,
        author_email: nil,
        committer_email: nil,
        blobs: {},
      }
    )

    rule_runs = rule_suite.rule_runs

    assert_equal 1, rule_runs.size
    assert_equal GitHub::UNKNOWN_REF_NAME, rule_suite.ref_name
    assert_equal GitHub::NULL_OID, rule_suite.before_oid
    assert_equal GitHub::PENDING_OID, rule_suite.after_oid
    assert rule_suite.runs_by_rule_type(:max_file_path_length).find(&:allowed?).present?
  end

  test "merges pre-commit and post-receive rule suites" do
    GitHub.flipper[:push_rulesets].enable

    ref_update = @org_repo_ref_updates.first

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    ref_ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "deletion", parameters: {})
    create(:repository_rule_configuration, repository_ruleset: ref_ruleset, rule_type: "branch_name_pattern", parameters: {
      pattern: "\\Afeature/.+",
      operator: "regex",
    })

    pre_commit_rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(
      @org_repo,
      nil,
      @org_repo.owner,
      {
        message: nil,
        author_email: nil,
        committer_email: nil,
        blobs: {},
      }
    )

    post_receive_rule_suite = RuleEngine::Evaluator.evaluate_rules_one(
      @org_repo,
      ref_update,
      @org_repo.owner,
      phase: RuleEngine::Types::Phase::PostReceive
    )

    rule_runs = post_receive_rule_suite.rule_runs

    assert_equal ref_update.refname, post_receive_rule_suite.ref_name
    assert_equal ref_update.before_oid, post_receive_rule_suite.before_oid
    assert_equal ref_update.after_oid, post_receive_rule_suite.after_oid

    assert_equal 3, rule_runs.size
    assert_equal post_receive_rule_suite.id, pre_commit_rule_suite.id
    assert post_receive_rule_suite.runs_by_rule_type(:max_file_path_length).find(&:allowed?).present?
    assert post_receive_rule_suite.runs_by_rule_type(:max_file_path_length).find(&:allowed?).present?
    assert post_receive_rule_suite.runs_by_rule_type(:branch_name_pattern).find(&:failed?).present?
  end

  test "updates pre-commit rule suite when no post-receive rules configured" do
    GitHub.flipper[:push_rulesets].enable

    ref_update = @org_repo_ref_updates.first

    push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 255
    })

    pre_commit_rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(
      @org_repo,
      nil,
      @org_repo.owner,
      {
        message: nil,
        author_email: nil,
        committer_email: nil,
        blobs: {},
      }
    )

    post_receive_rule_suite = RuleEngine::Evaluator.evaluate_rules_one(
      @org_repo,
      ref_update,
      @org_repo.owner,
      phase: RuleEngine::Types::Phase::PostReceive
    )

    rule_runs = post_receive_rule_suite.rule_runs

    assert_equal ref_update.refname, post_receive_rule_suite.ref_name
    assert_equal ref_update.before_oid, post_receive_rule_suite.before_oid
    assert_equal ref_update.after_oid, post_receive_rule_suite.after_oid

    assert_equal 1, rule_runs.size
    assert_equal post_receive_rule_suite.id, pre_commit_rule_suite.id
    assert post_receive_rule_suite.runs_by_rule_type(:max_file_path_length).find(&:allowed?).present?
  end

  test "skips max_ref_updates rules for a single ref update" do
    GitHub.kv.set("repo.max_ref_updates.#{@repo.id}", "1") # rubocop:todo GitHub/DoNotUseGlobalKv

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
      @repo.commits.find(signed_commit_oid)
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

  test "commit rule evaluation exposes metadata to violations" do
    GitHub.flipper[:push_rulesets].enable

    push_ruleset = build(:repository_ruleset, target: "push", source: @repo)
    push_rule = build(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "test_commit_rule")

    registered_rules = {
      "test_commit_rule" => TestCommitRule.new
    }
    push_metadata = {
      message: "Updating repo",
      author_email: nil,
      committer_email: nil,
      blobs: {
        "README.md" => "foo",
        "test.txt" => "bar"
      },
    }

    expected_metadata = {
      "README.md" => "metadata for README.md",
      "test.txt" => "metadata for test.txt"
    }

    RuleEngine::Evaluator.stub_const(:RULE_PROVIDERS, [TestPreReceiveRuleProvider.new]) do
      RuleEngine::Evaluator.stub_const(:REGISTERED_RULES, registered_rules) do
        rule_suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(
          @org_repo,
          nil,
          @org_repo.owner,
          push_metadata,
        )
        rule_runs = rule_suite.rule_runs

        assert_equal 1, rule_runs.size
        assert_equal expected_metadata, rule_runs.first&.evaluation_metadata
      end
    end
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
    GitHub.flipper[:rules_history].enable

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

  context "ruleset bypasses" do
    test "allows bypass for bypass_actor: Team / actor: team member" do
      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

      validate_bypass_allowed(@org_repo, ref_update, @org_admin) do
        RepositoryRulesetBypassActor.new(
          repository_ruleset: ruleset,
          actor: @team
        ).save!
      end
    end

    test "allows bypass for enterprise team bypass_actor" do
      GitHub.flipper[:enterprise_teams_enabled_for_organizations].enable
      GitHub.flipper[:enterprise_rulesets].enable
      GitHub.flipper[:member_privilege_rulesets].enable

      user = create(:user)
      enterprise_team = create(:enterprise_team, business: @business)
      enterprise_team_membership = EnterpriseTeamMembership.create!(enterprise_team: enterprise_team, user: user)

      ruleset = create(:repository_ruleset, :targets_all_orgs, :targets_all_repos, source: @business, target: "member_privilege")
      config = create(:repository_rule_configuration, rule_type: "restrict_repo_delete", repository_ruleset: ruleset)

      event = RuleEngine::Events::RepositoryOperationEvent.new(@biz_org_repo, user, { delete: nil }, dry_run: false)

      rule_suite = T.must(RuleEngine::GenericEvaluator.evaluate_rules(event).first)
      refute rule_suite.rules_fulfilled?, "Expected rules to be failing"
      refute rule_suite.action_permitted?, "Expected bypass to be denied before bypass is added"

      @biz_org_repo.enable_feature(:enterprise_rulesets_enterprise_teams)
      bypass_actor = RepositoryRulesetBypassActor.create(
        actor: enterprise_team,
        repository_ruleset: ruleset
      )

      @biz_org_repo.disable_feature(:enterprise_rulesets_enterprise_teams)
      rule_suite = T.must(RuleEngine::GenericEvaluator.evaluate_rules(event).first)
      refute rule_suite.rules_fulfilled?, "Expected rules to be failing"
      refute rule_suite.action_permitted?, "Expected bypass to be denied before FF is enabled"

      @biz_org_repo.enable_feature(:enterprise_rulesets_enterprise_teams)
      rule_suite = T.must(RuleEngine::GenericEvaluator.evaluate_rules(event).first)
      refute rule_suite.rules_fulfilled?, "Expected rules to be failing"
      assert rule_suite.action_permitted?, "Expected bypass to be pass"
    end

    test "allows bypass for bypass_actor: repo admin role / actor: repo admin role" do
      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

      validate_bypass_allowed(@org_repo, ref_update, @org_admin) do
        RepositoryRulesetBypassActor.new(
          repository_ruleset: ruleset,
          actor: RepositoryRole.find_by(name: "admin", owner: nil)
        ).save!
      end
    end

    test "denies bypass for direct commit bypass_actor: repo admin role (PR only) / actor: repo admin role" do
      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

      validate_bypass_denied(@org_repo, ref_update, @org_admin) do
        RepositoryRulesetBypassActor.new(
          repository_ruleset: ruleset,
          actor: RepositoryRole.find_by(name: "admin", owner: nil),
          bypass_mode: RepositoryRulesetBypassActor::BYPASS_MODES[:pull_request]
        ).save!
      end
    end

    test "denies bypass for bypass_actor: repo admin role / actor: write role" do
      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_member)

      validate_bypass_denied(@org_repo, ref_update, @org_member) do
        RepositoryRulesetBypassActor.new(
          repository_ruleset: ruleset,
          actor: RepositoryRole.find_by(name: "admin", owner: nil),
        ).save!
      end
    end

    test "allows bypass for bypass_actor: org admin / actor: org admin" do
      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

      validate_bypass_allowed(@org_repo, ref_update, @org_admin) do
        ruleset.bypass_mode = :org_bypass_any
        ruleset.save!
      end
    end

    test "denies bypass for direct commit bypass_actor: org admin (PR only) / actor: org admin" do
      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

      validate_bypass_denied(@org_repo, ref_update, @org_admin) do
        ruleset.bypass_mode = :org_bypass_prs_only
        ruleset.save!
      end
    end

    test "allows bypass for bypass_actor: write role / actor: write role" do
      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_member)

      validate_bypass_allowed(@org_repo, ref_update, @org_member) do
        RepositoryRulesetBypassActor.new(
          repository_ruleset: ruleset,
          actor: RepositoryRole.find_by(name: "write", owner: nil),
        ).save!
      end
    end

    test "allows bypass for bypass_actor: admin role / actor: write deploy key" do
      write_deploy_key = create :public_key, repository: @org_repo, read_only: false

      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

      validate_bypass_allowed(@org_repo, ref_update, write_deploy_key) do
        create(:repository_ruleset_bypass_actor, :repo_admin, bypass_mode: "any", repository_ruleset: ruleset)
      end
    end

    test "denies bypass for bypass_actor: admin role / actor: read deploy key" do
      read_deploy_key = create :public_key, repository: @org_repo, read_only: true

      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

      validate_bypass_denied(@org_repo, ref_update, read_deploy_key) do
        create(:repository_ruleset_bypass_actor, :repo_admin, bypass_mode: "any", repository_ruleset: ruleset)
      end
    end

    test "allows bypass by dependabot" do
      GitHub.stubs(dependency_graph_enabled?: true)
      GitHub.stubs(dependabot_enabled?: true)

      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_member)
      create(:repository_rule_configuration, repository_ruleset: ruleset)

      dependabot = create(:dependabot_integration)
      dependabot.install_on(
        @org,
        repositories: [@org_repo],
        installer: @org_admin,
        entry_point: :test_case
      )
      GitHub.stubs(dependabot_github_app: dependabot)
      assert @org.dependabot_installed?

      validate_bypass_allowed(@org_repo, ref_update, dependabot.bot) do
        RepositoryRulesetBypassActor.new(
          repository_ruleset: ruleset,
          actor: dependabot,
          bypass_mode: RepositoryRulesetBypassActor::BYPASS_MODES[:any]
        ).save!
      end
    end

    test "allows bypass for root repo admin on fork repo for push ruleset" do
      GitHub.flipper[:push_rulesets].enable

      org_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @org_repo.fork(forker: @org_member)
      end
      assert_equal :created, status

      push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
      create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
        max_file_path_length: 10
      })

      push_metadata = simple_push_metadata(@org_admin, "some-long-file-name", "contents")

      validate_bypass_allowed_push(org_repo_fork, "master", push_metadata, @org_admin) do
        create(:repository_ruleset_bypass_actor, :repo_admin, bypass_mode: "any", repository_ruleset: push_ruleset)
      end
    end

    test "denies bypass for fork repo admin on fork repo for push ruleset" do
      GitHub.flipper[:push_rulesets].enable

      org_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @org_repo.fork(forker: @org_member)
      end
      assert_equal :created, status

      push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
      create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
        max_file_path_length: 10
      })

      push_metadata = simple_push_metadata(@org_member, "some-long-file-name", "contents")

      validate_bypass_denied_push(org_repo_fork, "master", push_metadata, @org_member) do
        create(:repository_ruleset_bypass_actor, :repo_admin, bypass_mode: "any", repository_ruleset: push_ruleset)
      end
    end

    test "allows bypass for root org admin on cross-org fork repo for push ruleset" do
      GitHub.flipper[:push_rulesets].enable

      # Create a second organization
      org_admin_2 = create(:user)
      org_2 = create(:business_plus_organization, name: "org2", admin: org_admin_2)
      @org.add_member(org_admin_2)

      # Fork the repo to the second organization
      org_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @org_repo.fork(forker: org_admin_2, org: org_2)
      end
      assert_equal :created, status

      push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
      create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
        max_file_path_length: 10
      })

      push_metadata = simple_push_metadata(@org_admin, "some-long-file-name", "contents")

      validate_bypass_allowed_push(org_repo_fork, "master", push_metadata, @org_admin) do
        push_ruleset.bypass_mode = :org_bypass_any
        push_ruleset.save!
      end
    end

    test "denies bypass for fork org admin on cross-org fork repo for push ruleset" do
      GitHub.flipper[:push_rulesets].enable

      # Create a second organization
      org_admin_2 = create(:user)
      org_2 = create(:business_plus_organization, name: "org2", admin: org_admin_2)
      @org.add_member(org_admin_2)

      # Fork the repo to the second organization
      org_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @org_repo.fork(forker: org_admin_2, org: org_2)
      end
      assert_equal :created, status

      push_ruleset = create(:repository_ruleset, target: "push", source: @org_repo)
      create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
        max_file_path_length: 10
      })

      push_metadata = simple_push_metadata(org_admin_2, "some-long-file-name", "contents")

      validate_bypass_denied_push(org_repo_fork, "master", push_metadata, org_admin_2) do
        push_ruleset.bypass_mode = :org_bypass_any
        push_ruleset.save!
      end
    end

    test "allows bypass by deploy keys" do
      write_deploy_key = create :public_key, repository: @org_repo, read_only: false

      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

      validate_bypass_allowed(@org_repo, ref_update, write_deploy_key) do
        ruleset.deploy_key_bypass = true
        ruleset.save!
      end
    end

    test "disallow org admin/member bypass when only deploy keys are allowed" do
      repo_admin = create(:user)
      @org_repo.add_member(repo_admin, action: :admin)

      write_deploy_key = create :public_key, repository: @org_repo, read_only: false

      ruleset, ref_update = simple_ref_update_setup(@org_repo, @org_admin)

      validate_bypass_denied(@org_repo, ref_update, @org_admin) do
        ruleset.deploy_key_bypass = true
        ruleset.save!
      end

      validate_bypass_denied(@org_repo, ref_update, repo_admin) do
        ruleset.deploy_key_bypass = true
        ruleset.save!
      end

      validate_bypass_denied(@org_repo, ref_update, @org_member) do
        ruleset.deploy_key_bypass = true
        ruleset.save!
      end
    end

    test "allow all deploy keys to bypass" do
      key = Sham.ssh_public_key
      application = create :oauth_application, user: @repo_admin
      access = create :oauth_access, user: @repo_admin, application:, scopes: %w(user)

      user_oauth_key = @repo_admin.public_keys.create_with_verification \
          key:, verifier: @repo_admin, oauth_authorization: access.authorization
      repo_oauth_key = @repo.public_keys.create_with_verification \
          key:, verifier: @repo_admin, oauth_authorization: access.authorization
      user_created_deploy_key = create :public_key, repository: @repo, read_only: false

      ruleset, ref_update = simple_ref_update_setup(@repo, @repo_admin)

      # user oauth key: denied
      validate_bypass_denied(@repo, ref_update, user_oauth_key) do
        ruleset.deploy_key_bypass = true
        ruleset.save!
      end

      ruleset.deploy_key_bypass = false
      ruleset.save!

      # repo oauth key: allowed
      validate_bypass_allowed(@repo, ref_update, repo_oauth_key) do
        ruleset.deploy_key_bypass = true
        ruleset.save!
      end

      ruleset.deploy_key_bypass = false
      ruleset.save!

      # user-created deploy key: allowed
      validate_bypass_allowed(@repo, ref_update, user_created_deploy_key) do
        ruleset.deploy_key_bypass = true
        ruleset.save!
      end
    end
  end

  private

  def simple_ref_update_setup(repo, actor)
    ruleset = create(:repository_ruleset, :targets_default_branch, source: repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset, rule_type: "update", parameters: {
      update_allows_fetch_and_merge: false
    })

    ref = repo.heads.create("test", repo.heads["master"].target.first_parent_oid, actor)
    commit = ref.append_commit({ message: "commit", committer: actor }, actor) do |files|
      files.add "file-a", "some content"
    end
    ref_update = create_branch_update(repo, name: "master", before_oid: repo.heads["master"].target_oid, after_oid: commit.oid)

    [ruleset, ref_update]
  end

  class TestPreReceiveRuleProvider < RuleEngine::RuleProvider
    include RuleEngine::RuleProviders::GitRuleProvider

    def initialize
      super(identifier: "test")
    end

    sig { override.returns(RuleEngine::Types::Phase) }
    def phase
      RuleEngine::Types::Phase::PreReceive
    end

    sig do
      override
      .params(
        rule_config: RepositoryRuleConfiguration,
        actor: T.any(User, PublicKey, T::Hash[T.untyped, T.untyped]),
        repository: Repository,
        rule_run: T.nilable(RuleEngine::RuleRun)
      )
      .returns(T::Boolean)
    end
    def can_bypass?(rule_config, actor, repository, rule_run = nil)
      false
    end

    sig do
      override
      .params(
        repository: Repository,
        ref_names: T::Array[String]
      )
      .returns(T::Array[RepositoryRuleConfiguration])
    end
    def rule_for_branch_evaluators(repository, ref_names)
      []
    end

    sig do
      override
      .params(
        repository: Repository,
        ref_updates: T::Array[Git::Ref::Update],
        actor: T.nilable(T.any(User, PublicKey))
      )
      .returns(T::Array[RepositoryRuleConfiguration])
    end
    def rules_for_ref_updates(repository, ref_updates, actor)
      [
        RepositoryRuleConfiguration.create_provider_rule(
          provider: self,
          source: repository,
          rule_type: "test_commit_rule",
          matching_ref_names: ref_updates.map(&:refname),
          parameters: {}
        )
      ]
    end
  end

  class TestCommitRule < RuleEngine::CommitRule
    def initialize
      super(rule_name: "test_commit_rule", display_name: "For testing only")
    end

    sig do
      override
      .params(
        context: RuleEngine::RuleEvaluationContext,
        ref_update: Git::Ref::Update,
        rule_config: RepositoryRuleConfiguration,
        violations: T::Array[RuleEngine::Violation]
      )
      .returns(RuleEngine::RuleRun)
    end
    def generate_evaluation_result(context, ref_update, rule_config, violations)
      out_metadata = {}
      violations.each do |violation|
        candidate = T.cast(violation.candidate, RuleEngine::MetadataSources::Types::BlobCandidate)
        out_metadata[candidate.path] = violation.metadata
      end

      RuleEngine::RuleRun.failure(rule_config: rule_config,
        ref_update: ref_update,
        message: "failed",
        evaluation_metadata: out_metadata
      )
    end

    sig do
      override.params(
        context: RuleEngine::RuleEvaluationContext,
        ref_update: Git::Ref::Update,
        rule_config: RepositoryRuleConfiguration,
        candidate: RuleEngine::MetadataSources::Types::Candidate,
      ).returns(RuleEngine::EvaluationResult)
    end
    def evaluate_candidate(context, ref_update, rule_config, candidate)
      candidate = T.cast(candidate, RuleEngine::MetadataSources::Types::BlobCandidate)
      RuleEngine::EvaluationResult.failure(candidate: candidate, metadata: "metadata for #{candidate.path}")
    end

    sig { override.returns(T::Array[Symbol]) }
    def supported_metadata_types
      [:blob]
    end

    sig { override.returns(T::Array[Symbol]) }
    def supported_target_types
      [:push]
    end
  end
end
