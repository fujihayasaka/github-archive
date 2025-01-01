# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleSuiteTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do
    @repo = create(:repository)
    @user = create(:user)
    @repo.add_member @user, action: :write

    @org = create(:organization, plan: "business_plus")
    @org_admin = @org.admins.first
    @org_repo = create(:private_repository, owner: @org)
  end

  setup do
    @ref_update = create_branch_update(@repo)
    @org_ref_update = create_branch_update(@org_repo)
  end

  test "create and retrieve empty rule suite" do
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [], result: :allowed)
    suite.save!

    persisted_suite = RuleEngine::RuleSuite.find_by(repository: @ref_update.repository, ref_name: @ref_update.refname, before_oid: @ref_update.before_oid, after_oid: @ref_update.after_oid)
    refute persisted_suite.nil?
    assert_equal suite, persisted_suite
  end

  test "saves organization to rule suite for org owned repos" do
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [], result: :allowed)
    suite.save!
    assert_equal @repo.owner, suite.owner

    org_ref_update = create_branch_update(@org_repo)
    org_suite = RuleEngine::RuleSuite.for_ref_update(ref_update: org_ref_update, rule_runs: [], result: :allowed)
    org_suite.save!
    assert_equal @org, org_suite.owner
  end

  test "create and retrieve rule suite with runs" do
    run = RuleEngine::RuleRun.success(rule_config: create(:repository_rule_configuration), ref_update: @ref_update)
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [run])
    suite.save!

    persisted_suite = RuleEngine::RuleSuite.find_by(repository: @ref_update.repository, ref_name: @ref_update.refname, before_oid: @ref_update.before_oid, after_oid: @ref_update.after_oid)
    refute persisted_suite.nil?
    persisted_suite = T.must(persisted_suite)
    assert_equal suite, persisted_suite
    assert persisted_suite.allowed?
    assert_equal 1, persisted_suite.rule_runs.count
    assert_equal run, persisted_suite.rule_runs.first
  end

  test "saves bypassed rule suite" do
    ruleset = create(:repository_ruleset, :repo_admin_bypass)
    rule_config = create(:repository_rule_configuration, repository_ruleset: ruleset)
    run = RuleEngine::RuleRun.failure(rule_config: rule_config, ref_update: @ref_update, message: "failure")
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [run], actor: @repo.owner)
    suite.save!

    suite.check_bypasses!

    assert_predicate suite, :bypassed?
    assert_equal @repo.owner, suite.actor
  end

  test "doesn't save not bypassed rule suite" do
    ruleset = create(:repository_ruleset)
    rule_config = create(:repository_rule_configuration, repository_ruleset: ruleset)
    run = RuleEngine::RuleRun.failure(rule_config: rule_config, ref_update: @ref_update, message: "failure")
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [run], actor: @repo.owner)
    suite.save!

    suite.check_bypasses!

    refute_predicate suite, :bypassed?
  end

  test "publishes hydro event" do
    run_success = RuleEngine::RuleRun.success(rule_config: create(:repository_rule_configuration), ref_update: @ref_update)
    run_failure = RuleEngine::RuleRun.failure(rule_config: create(:repository_rule_configuration), ref_update: @ref_update, message: "A sad failure")
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [run_success, run_failure], actor: @user)
    suite.save!

    hydro_run_messages = [run_success, run_failure].map do |run|
      ruleset = T.must(run.rule_config&.repository_ruleset)
      hydro_success_message = {
        id: run.id,
        result: run.result,
        message: run.message,
        rule_type: run.rule_type,
        rule_suite_id: run.repository_rule_suite_id,
        rule_configuration_id: run.repository_rule_configuration_id,
        ruleset_id: ruleset.id,
        ruleset_name: ruleset.name,
        ruleset_target: ruleset.target,
        ruleset_source_type: ruleset.source.class.name,
        enforcement: ruleset.enforcement,
        rule_provider: run.rule_provider,
        violations: {}.to_json,
        evaluation_metadata: {}.to_json
      }
    end

    assert_hydro_published({
      repository: Hydro::EntitySerializer.repository(@repo),
      user: Hydro::EntitySerializer.user(@user),
      public_key: nil,
      rule_suite_id: suite.id,
      before_oid: suite.before_oid,
      after_oid: suite.after_oid,
      policy_oid: suite.policy_oid,
      ref_name: suite.ref_name,
      result: suite.result,
      rule_runs: hydro_run_messages
    }, schema: "github.repositories.v1.RuleSuiteEvaluation")
  end

  context "when rule suite is for protected branch" do
    test "publishes a hydro event" do
      pb = create(:protected_branch, repository: @repo, name: "*", pull_request_reviews_enforcement_level: :everyone)
      rule_provider = RuleEngine::RuleProviders::ProtectedBranchRuleProvider.new
      rules = rule_provider.rule_for_branch_evaluators(@repo, ["refs/heads/#{@repo.default_branch}"])
      pb_run = RuleEngine::RuleRun.failure(rule_config: T.must(rules.first), ref_update: @ref_update, message: "failure")
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [pb_run], actor: @user)
      suite.save!

      assert_hydro_published({
        repository: Hydro::EntitySerializer.repository(@repo),
        user: Hydro::EntitySerializer.user(@user),
        public_key: nil,
        rule_suite_id: suite.id,
        before_oid: suite.before_oid,
        after_oid: suite.after_oid,
        policy_oid: suite.policy_oid,
        ref_name: suite.ref_name,
        result: suite.result,
        rule_runs: [{
          id: pb_run.id,
          result: pb_run.result,
          message: pb_run.message,
          rule_type: pb_run.rule_type,
          rule_suite_id: pb_run.repository_rule_suite_id,
          rule_configuration_id: nil,
          ruleset_id: nil,
          ruleset_name: nil,
          ruleset_target: :RULESET_TARGET_NOT_APPLICABLE,
          ruleset_source_type: :RULESET_SOURCE_TYPE_NOT_APPLICABLE,
          enforcement: :ENABLED,
          rule_provider: "protected_branch",
          violations: {}.to_json,
          evaluation_metadata: {}.to_json
        }]
      }, schema: "github.repositories.v1.RuleSuiteEvaluation")
    end
  end

  test "hydro event for public key update" do
    write_deploy_key = create :public_key, repository: @repo, read_only: false
    run = RuleEngine::RuleRun.success(rule_config: create(:repository_rule_configuration), ref_update: @ref_update)
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [run], actor: write_deploy_key)
    suite.save!

    ruleset = T.must(run.rule_config&.repository_ruleset)
    hydro_run_message = {
      id: run.id,
      result: run.result,
      message: run.message,
      rule_type: run.rule_type,
      rule_suite_id: run.repository_rule_suite_id,
      rule_configuration_id: run.repository_rule_configuration_id,
      ruleset_id: ruleset.id,
      ruleset_name: ruleset.name,
      ruleset_target: ruleset.target,
      ruleset_source_type: ruleset.source.class.name,
      enforcement: ruleset.enforcement,
      rule_provider: run.rule_provider,
      violations: {}.to_json,
      evaluation_metadata: {}.to_json
    }

    assert_hydro_published({
      repository: Hydro::EntitySerializer.repository(@repo),
      user: nil,
      public_key: Hydro::EntitySerializer.public_key(write_deploy_key),
      rule_suite_id: suite.id,
      before_oid: suite.before_oid,
      after_oid: suite.after_oid,
      policy_oid: suite.policy_oid,
      ref_name: suite.ref_name,
      result: suite.result,
      rule_runs: [hydro_run_message]
    }, schema: "github.repositories.v1.RuleSuiteEvaluation")
  end

  context "#failure_messages" do
    test "returns formatted CLI message" do
      rule_config = create(:repository_rule_configuration)
      first_run = RuleEngine::RuleRun.failure(rule_config: rule_config, ref_update: @ref_update, message: "First failure")
      second_run = RuleEngine::RuleRun.failure(rule_config: rule_config, ref_update: @ref_update, message: "Second failure", cli_message: "Second CLI failure")
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [first_run, second_run], actor: @user)
      suite.save!

      assert_equal ["First failure", "Second CLI failure"], suite.failure_messages(from_cli: true, prefix: nil)
    end

    test "includes violations (less than 10)" do
      rule_config = create(:repository_rule_configuration)
      run = RuleEngine::RuleRun.failure(
        rule_config:,
        ref_update: @ref_update,
        message: "Failure",
        violations: 3.times.map { |n| { candidate: "Violation #{n + 1}" } },
      )

      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [run], actor: @user)
      suite.save!

      assert_equal ["Failure\nFound 3 violations:\n\nViolation 1\nViolation 2\nViolation 3"], suite.failure_messages(prefix: nil, exclude_violations: false)
    end

    test "includes violations (up than 10)" do
      rule_config = create(:repository_rule_configuration)
      run = RuleEngine::RuleRun.failure(
        rule_config:,
        ref_update: @ref_update,
        message: "Failure",
        violations: 100.times.map { |n| { candidate: "Violation #{n + 1}" } },
      )

      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [run], actor: @user)
      suite.save!

      formatted_violations = 10.times.map { |n| "Violation #{n + 1}" }.join("\n")

      assert_equal ["Failure\nFound 100 violations (showing first 10):\n\n#{formatted_violations}"], suite.failure_messages(prefix: nil, exclude_violations: false)
    end
  end

  context "delete repo" do
    test "purged when repo purged" do
      run = RuleEngine::RuleRun.success(rule_config: create(:repository_rule_configuration), ref_update: @ref_update)
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [run])
      suite.save!

      persisted_suite = RuleEngine::RuleSuite.find_by(repository: @ref_update.repository, ref_name: @ref_update.refname, before_oid: @ref_update.before_oid, after_oid: @ref_update.after_oid)
      refute persisted_suite.nil?
      persisted_suite = T.must(persisted_suite)
      assert_equal 1, persisted_suite.rule_runs.count
      assert_equal run, persisted_suite.rule_runs.first

      perform_enqueued_jobs(only: RepositoryOrchestration) { @ref_update.repository.remove(User.ghost) }
      assert persisted_suite.reload

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob, DestroyDependentRecordsJob]) { @ref_update.repository.purge }
      assert RuleEngine::RuleSuite.where(repository: @ref_update.repository).empty?
    end

    test "is deleted with repository" do
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @ref_update, rule_runs: [], result: :allowed)
      suite.save!
      other_suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [], result: :allowed)
      other_suite.save!

      assert_destroyed_in_background_with_parent do |config|
        config.parent_record = @repo
        config.expect_destroyed = [suite]
        config.expect_not_destroyed = [other_suite]
      end
    end
  end

  context "source results" do
    test "does not set evaluate mode result without evaluate mode rules" do
      rc1 = create(:repository_rule_configuration)

      run1 = RuleEngine::RuleRun.success(rule_config: rc1, ref_update: @org_ref_update)
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert suite.allowed?
      assert_equal 1, suite.source_results.size
      suite_source_result = T.must(suite.source_results.first)
      assert_equal rc1.repository_ruleset.source, suite_source_result.source
      assert suite_source_result.result_allowed?
      assert suite_source_result.evaluate_result_none?
    end

    test "does not set actual result to failed when only evaluate mode rule fails" do
      rs = create(:repository_ruleset, :with_rules, source: @org_repo, enforcement: "evaluate")

      run1 = RuleEngine::RuleRun.failure(rule_config: rs.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert suite.allowed?
      assert_equal 1, suite.source_results.size
      suite_source_result = T.must(suite.source_results.first)
      assert_equal @org_repo, suite_source_result.source
      assert suite_source_result.result_none?
      assert suite_source_result.evaluate_result_failed?
    end

    test "sets evaluate mode result for failed evaluate mode rules" do
      rs1 = create(:repository_ruleset, :with_rules, source: @org_repo)
      rs2 = create(:repository_ruleset, :with_rules, source: @org_repo, enforcement: "evaluate")

      run1 = RuleEngine::RuleRun.success(rule_config: rs1.rule_configurations.first, ref_update: @org_ref_update)
      run2 = RuleEngine::RuleRun.failure(rule_config: rs2.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1, run2], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert suite.allowed?
      assert_equal 1, suite.source_results.size
      suite_source_result = T.must(suite.source_results.first)
      assert_equal @org_repo, suite_source_result.source
      assert suite_source_result.result_allowed?
      assert suite_source_result.evaluate_result_failed?
    end

    test "sets evaluate mode result for allowed evaluate mode rules" do
      rs1 = create(:repository_ruleset, :with_rules, source: @org_repo)
      rs2 = create(:repository_ruleset, :with_rules, source: @org_repo, enforcement: "evaluate")

      run1 = RuleEngine::RuleRun.success(rule_config: rs1.rule_configurations.first, ref_update: @org_ref_update)
      run2 = RuleEngine::RuleRun.success(rule_config: rs2.rule_configurations.first, ref_update: @org_ref_update)
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1, run2], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert suite.allowed?
      assert_equal 1, suite.source_results.size
      suite_source_result = T.must(suite.source_results.first)
      assert_equal @org_repo, suite_source_result.source
      assert suite_source_result.result_allowed?
      assert suite_source_result.evaluate_result_allowed?
    end

    test "does not sets evaluate mode result to bypassed when evaluate rules cannot be 'bypassed'" do
      rs1 = create(:repository_ruleset, :with_rules, :repo_admin_bypass, source: @org_repo)
      rs2 = create(:repository_ruleset, :with_rules, enforcement: "evaluate", source: @org_repo)

      run1 = RuleEngine::RuleRun.failure(rule_config: rs1.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      run2 = RuleEngine::RuleRun.failure(rule_config: rs2.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1, run2], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert suite.bypassed?
      assert_equal 1, suite.source_results.size
      suite_source_result = T.must(suite.source_results.first)
      assert_equal @org_repo, suite_source_result.source
      assert suite_source_result.result_bypassed?
      assert suite_source_result.evaluate_result_failed?
    end

    test "sets evaluate mode result to bypassed when evaluate rules are 'bypassed'" do
      rs1 = create(:repository_ruleset, :with_rules, :repo_admin_bypass, source: @org_repo)
      rs2 = create(:repository_ruleset, :with_rules, :repo_admin_bypass, enforcement: "evaluate", source: @org_repo)

      run1 = RuleEngine::RuleRun.failure(rule_config: rs1.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      run2 = RuleEngine::RuleRun.failure(rule_config: rs2.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1, run2], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert suite.bypassed?
      assert_equal 1, suite.source_results.size
      suite_source_result = T.must(suite.source_results.first)
      assert_equal @org_repo, suite_source_result.source
      assert suite_source_result.result_bypassed?
      assert suite_source_result.evaluate_result_bypassed?
    end

    test "sets evaluate mode result to bypassed when all active rules pass but evaluate rules can be bypassed" do
      rs1 = create(:repository_ruleset, :with_rules, :repo_admin_bypass, source: @org_repo)
      rs2 = create(:repository_ruleset, :with_rules, :repo_admin_bypass, enforcement: "evaluate", source: @org_repo)

      run1 = RuleEngine::RuleRun.success(rule_config: rs1.rule_configurations.first, ref_update: @org_ref_update)
      run2 = RuleEngine::RuleRun.failure(rule_config: rs2.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1, run2], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert suite.allowed?
      assert_equal 1, suite.source_results.size
      suite_source_result = T.must(suite.source_results.first)
      assert_equal @org_repo, suite_source_result.source
      assert suite_source_result.result_allowed?
      assert suite_source_result.evaluate_result_bypassed?
    end

    test "records source results for two sources" do
      rs1 = create(:repository_ruleset, :with_rules, source: @org)
      rs2 = create(:repository_ruleset, :with_rules, source: @org_repo)

      run1 = RuleEngine::RuleRun.success(rule_config: rs1.rule_configurations.first, ref_update: @org_ref_update)
      run2 = RuleEngine::RuleRun.failure(rule_config: rs2.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1, run2], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert suite.failed?
      assert_equal 2, suite.source_results.size
      assert_same_elements [@org_repo, @org], suite.source_results.map(&:source)
      assert T.must(suite.source_results.find { |r| r.source == @org }).result_allowed?
      assert T.must(suite.source_results.find { |r| r.source == @org_repo }).result_failed?
    end

    test "records source results for two sources with merge" do
      rs1 = create(:repository_ruleset, :with_rules, source: @org)
      rs2 = create(:repository_ruleset, :with_rules, source: @org_repo)

      run1 = RuleEngine::RuleRun.success(rule_config: rs1.rule_configurations.first, ref_update: @org_ref_update)
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1], actor: @org_admin)
      suite.save!

      run2 = RuleEngine::RuleRun.failure(rule_config: rs2.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      RuleEngine::RuleSuite.merge(suite:, ref_update: @org_ref_update, rule_runs: [run2], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert suite.failed?
      assert_equal 2, suite.source_results.size
      assert_same_elements [@org_repo, @org], suite.source_results.map(&:source)
      assert T.must(suite.source_results.find { |r| r.source == @org }).result_allowed?
      assert T.must(suite.source_results.find { |r| r.source == @org_repo }).result_failed?
    end

    test "records respective source result bypass when one source can be bypassed and the other cannot" do
      rs1 = create(:repository_ruleset, :with_rules, source: @org)
      rs2 = create(:repository_ruleset, :with_rules, :repo_admin_bypass, source: @org_repo)

      run1 = RuleEngine::RuleRun.failure(rule_config: rs1.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      run2 = RuleEngine::RuleRun.failure(rule_config: rs2.rule_configurations.first, ref_update: @org_ref_update, message: "failure")
      suite = RuleEngine::RuleSuite.for_ref_update(ref_update: @org_ref_update, rule_runs: [run1, run2], actor: @org_admin)
      suite.check_bypasses!
      suite.save!

      assert suite.failed?
      assert_equal 2, suite.source_results.size
      assert_same_elements [@org_repo, @org], suite.source_results.map(&:source)
      assert T.must(suite.source_results.find { |r| r.source == @org }).result_failed?
      assert T.must(suite.source_results.find { |r| r.source == @org_repo }).result_bypassed?
    end
  end
end
