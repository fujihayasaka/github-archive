# typed: true
# frozen_string_literal: true

require "test_helper"

class RequiredStatusChecksRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include PushTestHelper
  include GitHub::MachinistHelpers

  EXAMPLE_REPO = :simple
  MAIN_SHA = "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"
  BRANCH_SHA = "e91a032dc9f19058a375fb3db68c9dda73527d13"

  fixtures do
    @user = create(:user)
    @integration = create(:integration)
    @repo = create(:repository, owner: @user, from_example: EXAMPLE_REPO)
  end

  setup do
    @ref_update = create_branch_update(
      @repo,
      before_oid: MAIN_SHA,
      after_oid: BRANCH_SHA,
    )

    @context = RuleEngine::RuleEvaluationContext.new(@repo, @user)

    @required_status_checks = [create_required_check("test")]

    @parameters = {
      strict_required_status_checks_policy: false
    }

    @rule_configs = [
      build(
        :repository_rule_configuration,
        rule_type: :required_status_checks,
        parameters: @parameters,
        lazy_parameters: {
          required_status_checks: lambda { @required_status_checks }
        }
      )
    ]

    @rule = RuleEngine::Rules::RequiredStatusChecksRule.new
  end

  test "returns a fulfilled decision the only check is fulfilled" do
    successful_check("test")

    rule_runs = @rule.evaluate(@context, @ref_update, @rule_configs)

    assert_equal 1, rule_runs.size
    assert_predicate rule_runs.first, :allowed?
  end

  test "returns a fulfilled decision the only check is fulfilled by the required integration" do
    @required_status_checks.first.integration = @integration
    successful_check("test", creator: @integration.bot)

    rule_runs = @rule.evaluate(@context, @ref_update, @rule_configs)

    assert_equal 1, rule_runs.length
    assert_predicate rule_runs.first, :allowed?
  end

  test "returns an unfulfilled decision when the only check is expected" do
    rule_runs = @rule.evaluate(@context, @ref_update, @rule_configs)

    assert_equal 1, rule_runs.length
    assert_predicate rule_runs.first, :failed?
    run = rule_runs.first
    assert_equal "Required status check \"test\" is expected.", run.message
    assert_equal :required_status_checks, run.reason_code
  end

  test "returns an unfulfilled decision when all checks is are expected" do
    @required_status_checks << create_required_check("test2")

    rule_runs = @rule.evaluate(@context, @ref_update, @rule_configs)

    assert_equal 1, rule_runs.length
    assert_predicate rule_runs.first, :failed?
    run = rule_runs.first
    assert_equal "2 of 2 required status checks are expected.", run.message
    assert_equal :required_status_checks, run.reason_code
  end

  test "returns an unfulfilled decision when all checks are in unsuccessful states" do
    @required_status_checks << create_required_check("test2")
    failed_check("test2")

    rule_runs = @rule.evaluate(@context, @ref_update, @rule_configs)

    assert_equal 1, rule_runs.length
    assert_predicate rule_runs.first, :failed?
    run = rule_runs.first
    assert_equal "2 of 2 required status checks have not succeeded: 1 expected and 1 failing.", run.message
    assert_equal :required_status_checks, run.reason_code
  end

  test "returns an unfilfilled decision when the only check is fulfilled by the wrong actor" do
    @required_status_checks.first.integration = @integration
    successful_check("test", creator: @user)

    rule_runs = @rule.evaluate(@context, @ref_update, @rule_configs)

    assert_equal 1, rule_runs.length
    assert_predicate rule_runs.first, :failed?
    run = rule_runs.first
    assert_equal "Required status check \"test\" was not set by the expected GitHub app.", run.message
    assert_equal :required_status_check_integrations, run.reason_code
  end

  test "returns an unfilfilled decision when several checks are fulfilled by the wrong actor" do
    @required_status_checks.first.integration = @integration
    @required_status_checks << create_required_check("test2", integration: @integration)
    successful_check("test", creator: @user)
    successful_check("test2", creator: @user)

    rule_runs = @rule.evaluate(@context, @ref_update, @rule_configs)

    assert_equal 1, rule_runs.length
    assert_predicate rule_runs.first, :failed?
    run = rule_runs.first
    assert_equal "Required status checks \"test\" and \"test2\" were not set by the expected GitHub apps.", run.message
    assert_equal :required_status_check_integrations, run.reason_code
  end

  test "returns a fulfilled decision when multiple check runs with the same name are fulfilled by their respective actors" do
    integration1 = create(:integration, default_permissions: { "checks" => :write })
    integration2 = create(:integration, default_permissions: { "checks" => :write })
    make_integration_installation(integration: integration1, repository: @repo)
    make_integration_installation(integration: integration2, repository: @repo)
    required_status_checks = [
      create_required_check("build", integration: integration1),
       create_required_check("build", integration: integration2)
      ]

    rule_configs = [
      build(
        :repository_rule_configuration,
        rule_type: :required_status_checks,
        parameters: @parameters,
        lazy_parameters: {
          required_status_checks: lambda { required_status_checks }
        }
      )
    ]

    check_suite_a_1 = CheckSuite.create!(repository_id: @repo.id, head_sha: @ref_update.after_oid, github_app_id: integration1.id)
    check_suite_b_1 = CheckSuite.create!(repository_id: @repo.id, head_sha: @ref_update.after_oid, github_app_id: integration2.id)
    check_run_a_1 = completed_check_run("build", check_suite_a_1) # uses first integration
    check_run_b_1 = completed_check_run("build", check_suite_b_1) # uses second integration

    rule_runs = @rule.evaluate(@context, @ref_update, rule_configs)

    assert_equal 1, rule_runs.length
    refute_predicate rule_runs.first, :failed?
    run = rule_runs.first
    assert_nil run.message
    assert_equal :required_status_checks, run.reason_code
  end

  context "ignore_update_types" do
    test "should return [:deletion] when a rule config with bypass on create disabled" do
      config = config_with_checks([{
        context: "test",
        integration_id: @integration.id
      }])

      assert_equal @rule.ignore_update_types(config), [:deletion]
    end
    test "should return [:creation, :deletion] when a rule config with bypass on create enabled" do
      config = config_with_creation_bypass([{
        context: "test",
        integration_id: @integration.id
      }])

      assert_equal @rule.ignore_update_types(config), [:creation, :deletion]
    end
  end

  context "ref_update_ignored?" do
    test "should return false when do_not_enforce_on_create is disabled" do
      new_ref = create_branch_update(@repo)
      refute @rule.ref_update_ignored?(@context, new_ref, config_with_checks({
        context: "test",
        integration_id: @integration.id
      }))
    end

    test "should return true when do_not_enforce_on_create is enabled" do
      new_ref = create_branch_update(@repo)
      assert @rule.ref_update_ignored?(@context, new_ref, config_with_creation_bypass({
        context: "test",
        integration_id: @integration.id
      }))
    end

    test "should return true when ref_update is a :deletion" do
      delete_ref = create_branch_update(@repo, before_oid: create_random_sha, after_oid: GitHub::NULL_OID)
      assert @rule.ref_update_ignored?(@context, delete_ref, config_with_creation_bypass({
        context: "test",
        integration_id: @integration.id
      }))
    end
  end

  context "JSON-backed checks" do
    test "returns a fulfilled decision the only check is fulfilled by the required integration" do
      successful_check("test", creator: @integration.bot)

      config = config_with_checks([{
        context: "test",
        integration_id: @integration.id
      }])

      rule_runs = @rule.evaluate(@context, @ref_update, [config])

      assert_equal 1, rule_runs.length
      assert_predicate rule_runs.first, :allowed?
    end

    test "returns an unfulfilled decision when the only check is expected" do
      config = config_with_checks([{
        context: "test"
      }])

      rule_runs = @rule.evaluate(@context, @ref_update, [config])

      assert_equal 1, rule_runs.length
      assert_predicate rule_runs.first, :failed?
      run = rule_runs.first
      assert_equal "Required status check \"test\" is expected.", run.message
      assert_equal :required_status_checks, run.reason_code
    end
  end

  def config_with_checks(checks_json_array)
    build(
      :repository_rule_configuration,
      rule_type: :required_status_checks,
      parameters: {
        strict_required_status_checks_policy: false,
        required_status_checks: checks_json_array
      }
    )
  end

  def config_with_creation_bypass(checks_json_array)
    build(
      :repository_rule_configuration,
      rule_type: :required_status_checks,
      parameters: {
        strict_required_status_checks_policy: false,
        required_status_checks: checks_json_array,
        do_not_enforce_on_create: true,
      }
    )
  end

  def create_required_check(context, integration: nil)
    RequiredStatusCheck.create(
      context: context,
      integration: integration,
    )
  end

  def successful_check(context, creator: @user)
    create(
      :status,
      context: context,
      state: :success,
      sha: BRANCH_SHA,
      repository: @repo,
      creator: creator,
    )
  end

  def completed_check_run(name, check_suite, conclusion: :success)
    create(
      :completed_check_run,
      name: name,
      check_suite: check_suite,
      conclusion: conclusion,
    )
  end

  def failed_check(context)
    create(
      :status,
      context: context,
      state: :failure,
      sha: BRANCH_SHA,
      repository: @repo,
      creator: @user,
    )
  end
end
