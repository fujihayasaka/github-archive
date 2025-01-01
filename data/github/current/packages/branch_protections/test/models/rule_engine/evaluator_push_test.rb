# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"
require "test_helpers/dependabot_github_app_helper"

class RuleEngineEvaluatorPushTest < GitHub::TestCase
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

  test "evaluates push targeting rules during pre-receive phase" do
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

  test "commit rule evaluation exposes metadata to violations" do
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

  test "enterprise push rulesets inherit to user forks of repos" do
    user_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @biz_org_repo.fork(forker: @biz_owner)
    end
    assert_equal :created, status

    push_ruleset = create(:repository_ruleset, :targets_all_orgs, :targets_all_repos, target: "push", source: @business)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    ref_update = create_ref_update(user_repo_fork)
    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(user_repo_fork, [ref_update], user_repo_fork.owner, phase: RuleEngine::Types::Phase::PreReceive).first)
    rule_runs = rule_suite.rule_runs.to_a

    if GitHub.flipper[:enterprise_rulesets].enabled?
      assert_equal 1, rule_runs.size
      assert_equal push_ruleset, rule_runs.first&.source_ruleset
    else
      assert_equal 0, rule_runs.size
    end
  end

  test "enterprise push rulesets inherit to org forks of repos" do
    org_repo_fork, status = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      @biz_org_repo.fork(forker: @biz_owner, org: @another_biz_org)
    end
    assert_equal :created, status

    push_ruleset = create(:repository_ruleset, :targets_all_orgs, :targets_all_repos, target: "push", source: @business)
    create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    ref_update = create_ref_update(org_repo_fork)
    rule_suite = T.must(RuleEngine::Evaluator.evaluate_rules(org_repo_fork, [ref_update], org_repo_fork.owner, phase: RuleEngine::Types::Phase::PreReceive).first)
    rule_runs = rule_suite.rule_runs.to_a

    if GitHub.flipper[:enterprise_rulesets].enabled?
      assert_equal 1, rule_runs.size
      assert_equal push_ruleset, rule_runs.first&.source_ruleset
    else
      assert_equal 0, rule_runs.size
    end
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
