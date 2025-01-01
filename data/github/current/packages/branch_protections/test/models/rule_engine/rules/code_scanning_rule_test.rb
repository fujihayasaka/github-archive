# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEnginePushesCodeScanningRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include RulesEngine::CandidateTestHelper

  fixtures do
    make_trusted_oauth_apps_owner
    @dependabot_app = create(:dependabot_integration)
    @repo = create(:repository)
    @user = create(:user)
    @repo.add_member @user, action: :write
    make_trusted_oauth_apps_owner
    @integration = create(:code_scanning_integration)
    check_suite = create(:check_suite, repository: @repo, github_app: @integration)
    code_scanning_check_suite = create(:code_scanning_check_suite, repository: @repo, check_suite: check_suite)
  end

  setup do
    # this ensures that the tests cannot silently fail the rule because of a VCR misconfiguration
    # as we would report this as an error to Failbot.
    Failbot.expects(:report).never
    example_repo :simple, @repo
    @context = RuleEngine::RuleEvaluationContext.new(@repo)
    @rule = RuleEngine::Rules::CodeScanningRule.new
    GitHub.stubs(:dependabot_enabled?).returns(true) if GitHub.enterprise?
    GitHub.remove_instance_variable(:@dependabot_github_app) if GitHub.instance_variable_defined?(:@dependabot_github_app)
    GitHub.remove_instance_variable(:@dependabot_github_app_bot) if GitHub.instance_variable_defined?(:@dependabot_github_app_bot)
    # Ensure we preload the Dependabot bot User before the test as we do not expect
    # the query to typically execute
    GitHub.dependabot_github_app_bot
  end

  test "enums map to correct values" do
    assert_equal Turboscan::Proto::EvalRefUpdateRulesRequest::SeverityChoice::SEVERITY_NONE, RuleEngine::Rules::CodeScanningRule::SEVERITIES[RuleEngine::Rules::CodeScanningRule::SEVERITY_NONE]
    assert_equal Turboscan::Proto::EvalRefUpdateRulesRequest::SeverityChoice::SEVERITY_ERRORS, RuleEngine::Rules::CodeScanningRule::SEVERITIES[RuleEngine::Rules::CodeScanningRule::SEVERITY_ERRORS]
    assert_equal Turboscan::Proto::EvalRefUpdateRulesRequest::SeverityChoice::SEVERITY_ERRORS_AND_WARNINGS, RuleEngine::Rules::CodeScanningRule::SEVERITIES[RuleEngine::Rules::CodeScanningRule::SEVERITY_ERRORS_AND_WARNINGS]
    assert_equal Turboscan::Proto::EvalRefUpdateRulesRequest::SeverityChoice::SEVERITY_ALL, RuleEngine::Rules::CodeScanningRule::SEVERITIES[RuleEngine::Rules::CodeScanningRule::SEVERITY_ALL]

    assert_equal Turboscan::Proto::EvalRefUpdateRulesRequest::SecuritySeverityChoice::SECURITY_SEVERITY_NONE, RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITIES[RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_NONE]
    assert_equal Turboscan::Proto::EvalRefUpdateRulesRequest::SecuritySeverityChoice::SECURITY_SEVERITY_CRITICAL, RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITIES[RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_CRITICAL]
    assert_equal Turboscan::Proto::EvalRefUpdateRulesRequest::SecuritySeverityChoice::SECURITY_SEVERITY_HIGH_OR_HIGHER, RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITIES[RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_HIGH_OR_HIGHER]
    assert_equal Turboscan::Proto::EvalRefUpdateRulesRequest::SecuritySeverityChoice::SECURITY_SEVERITY_MEDIUM_OR_HIGHER, RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITIES[RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_MEDIUM_OR_HIGHER]
    assert_equal Turboscan::Proto::EvalRefUpdateRulesRequest::SecuritySeverityChoice::SECURITY_SEVERITY_ALL, RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITIES[RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_ALL]
  end

  test "allow dependabot commits" do
    merge_commit = @repo.commits.create_merge_commit(GitHub.dependabot_github_app_bot, @repo.default_branch, "cr-line-endings").first

    pull = PullRequest.create_for!(@repo, user: GitHub.dependabot_github_app_bot,
      base: "master", head: "cr-line-endings", title: "convert to CR line ending")

    pr_ref_update = Git::Branch::Update.new(repository: @repo, refname: "refs/heads/#{pull.base_ref_name}",
        before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid,
        pull_request: pull)

    create(:push, pusher: GitHub.dependabot_github_app_bot, ref: "refs/heads/cr-line-endings", after: pull.head_sha, repository: @repo)

    context = RuleEngine::RuleEvaluationContext.new(@repo, additional_context: { merge_box_evaluation: true })

    rule_config = build(
      :repository_rule_configuration,
      rule_type: "code_scanning",
      parameters: {
        code_scanning_tools: [
          { tool: "CodeQL", alerts_threshold: RuleEngine::Rules::CodeScanningRule::SEVERITY_ALL, security_alerts_threshold: RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_ALL },
        ],
      }
    )

    assert_empty rule_config.parameter_errors

    # make sure request includes is_dependabot: true
    body_params_matcher = lambda do |actual, _|
      JSON.parse(actual.body).slice("isDependabot") == { "isDependabot" => true }
    end

    VCR.use_cassette("code-scanning/eval-ref-update-rules-pass-dependabot", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
      rule_run, = @rule.evaluate(context, pr_ref_update, [rule_config])
      assert_equal "allowed", rule_run.result, rule_run.message
    end
  end

  test "require a scan for modified dependabot pull requests" do
    @repo.heads.find("cr-line-endings").append_commit({ message: "new commit", committer: @user }, @user) do |files|
      files.add("new_file.rb", "really amazing content")
    end

    merge_commit = @repo.commits.create_merge_commit(GitHub.dependabot_github_app_bot, @repo.default_branch, "cr-line-endings").first

    pull = PullRequest.create_for!(@repo, user: GitHub.dependabot_github_app_bot,
      base: "master", head: "cr-line-endings", title: "convert to CR line ending")

    pr_ref_update = Git::Branch::Update.new(repository: @repo, refname: "refs/heads/#{pull.base_ref_name}",
        before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid,
        pull_request: pull)

    create(:push, pusher: @user, ref: "refs/heads/cr-line-endings", after: pull.head_sha, repository: @repo)

    context = RuleEngine::RuleEvaluationContext.new(@repo, additional_context: { merge_box_evaluation: true })

    rule_config = build(
      :repository_rule_configuration,
      rule_type: "code_scanning",
      parameters: {
        code_scanning_tools: [
          { tool: "CodeQL", alerts_threshold: RuleEngine::Rules::CodeScanningRule::SEVERITY_ALL, security_alerts_threshold: RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_ALL },
        ],
      }
    )

    assert_empty rule_config.parameter_errors

    # make sure request does not think this is dependabot
    body_params_matcher = lambda do |actual, _|
      JSON.parse(actual.body).slice("isDependabot") != { "isDependabot" => true }
    end

    VCR.use_cassette("code-scanning/eval-ref-update-rules-pass1", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
      rule_run, = @rule.evaluate(context, pr_ref_update, [rule_config])
      assert_equal "allowed", rule_run.result
    end
  end

  test "exercise the rule code" do
    merge_commit = @repo.commits.create_merge_commit(@user, @repo.default_branch, "cr-line-endings").first

    pull = PullRequest.create_for!(@repo, user: @user,
      base: "master", head: "cr-line-endings", title: "convert to CR line ending")

    pr_ref_update = Git::Branch::Update.new(repository: @repo, refname: "refs/heads/#{pull.base_ref_name}",
        before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid,
        pull_request: pull)

    context = RuleEngine::RuleEvaluationContext.new(@repo, additional_context: { merge_box_evaluation: true })

    ruleset = create(:repository_ruleset, :targets_default_branch, source: @repo)

    GitHub.flipper[:code_scanning_thresholds_rule].enable

    rule_config = create(
      :repository_rule_configuration,
      repository_ruleset: ruleset,
      rule_type: "code_scanning",
      parameters: {
        code_scanning_tools: [
          { tool: "ESLint", alerts_threshold: RuleEngine::Rules::CodeScanningRule::SEVERITY_NONE, security_alerts_threshold: RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_NONE },
        ],
      }
    )

    assert_empty rule_config.parameter_errors

    evaluator = T.must(BranchRuleEvaluator.for_repository_with_branch_name(@repo, @repo.default_branch))
    assert evaluator.code_scanning_enabled?
    refute evaluator.codeql_required?

    rule_config.parameters = {
      code_scanning_tools: [
        { tool: "CodeQL", alerts_threshold: RuleEngine::Rules::CodeScanningRule::SEVERITY_ALL, security_alerts_threshold: RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_ALL },
      ],
    }
    rule_config.save!

    assert_empty rule_config.parameter_errors

    evaluator = T.must(BranchRuleEvaluator.for_repository_with_branch_name(@repo, @repo.default_branch))
    assert evaluator.code_scanning_enabled?
    assert evaluator.codeql_required?

    GitHub.flipper[:code_scanning_pr_fixed_alerts].disable

    body_params_matcher = lambda do |actual, _|
      assert_equal(
        {
          "repositoryId" => @repo.id.to_s,
          "baseRefBytes" => Base64.strict_encode64("refs/heads/#{pull.base_ref_name}"),
          "headCommitOid" => pull.head_sha,
          "fileChanges" => [{
            "filePath" => "a", "changes" => [{
              "added" => true,
              "startLine" => 1,
              "endLine" => 1,
            }]
          }],
          "ruleConfigs" => [{
            "toolConfigs" => [{
              "name" => "CodeQL",
              "alertsThreshold" => "SEVERITY_ALL",
              "securityAlertsThreshold" => "SECURITY_SEVERITY_ALL"
            }]
          }]
        },
        JSON.parse(actual.body)
      )
    end

    VCR.use_cassette("code-scanning/eval-ref-update-rules-fail1", persist_with: :turboscan, match_requests_on: [:method, :uri, body_params_matcher]) do
      rule_run, = @rule.evaluate(context, pr_ref_update, [rule_config])
      assert_equal "failed", rule_run.result
    end
  end

  test "works without a pull request" do
    merge_commit = @repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first

    pr_ref_update = Git::Ref::Update.new(repository: @repo, refname: "refs/heads/master",
        before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid)

    context = RuleEngine::RuleEvaluationContext.new(@repo, additional_context: { merge_box_evaluation: false })
    rule_config = build(
      :repository_rule_configuration,
      rule_type: "code_scanning",
      parameters: {
        code_scanning_tools: [
          { tool: "CodeQL", alerts_threshold: RuleEngine::Rules::CodeScanningRule::SEVERITY_NONE, security_alerts_threshold: RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_NONE },
        ],
      }
    )

    assert_empty rule_config.parameter_errors

    VCR.use_cassette("code-scanning/eval-ref-update-rules-pass1", persist_with: :turboscan) do
      rule_run, = @rule.evaluate(context, pr_ref_update, [rule_config])
      assert_equal "allowed", rule_run.result, rule_run.message
    end
  end

  test "Twirp errors block the rule" do
    Failbot.expects(:report).once

    merge_commit = @repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first

    pull = PullRequest.create_for!(@repo, user: @user,
      base: "master", head: "cr-line-endings", title: "convert to CR line ending")

    pr_ref_update = Git::Branch::Update.new(repository: @repo, refname: "refs/heads/#{pull.base_ref_name}",
        before_oid:  merge_commit.parent_oids.first, after_oid: merge_commit.oid,
        pull_request: pull)

    context = RuleEngine::RuleEvaluationContext.new(@repo, additional_context: { merge_box_evaluation: true })
    rule_configs = [
      build(
        :repository_rule_configuration,
        rule_type: "code_scanning",
        parameters: {
          code_scanning_tools: [
            { tool: "CodeQL", alerts_threshold: RuleEngine::Rules::CodeScanningRule::SEVERITY_ALL, security_alerts_threshold: RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_ALL },
          ],
        }
      ),
      build(
        :repository_rule_configuration,
        rule_type: "code_scanning",
        parameters: {
          code_scanning_tools: [
            { tool: "CodeQL", alerts_threshold: RuleEngine::Rules::CodeScanningRule::SEVERITY_ALL, security_alerts_threshold: RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_ALL },
          ],
        }
      )
    ]

    assert_empty rule_configs.map(&:parameter_errors).reject(&:empty?)

    response = Twirp::ClientResp.new(error: Twirp::Error.internal("test error"))
    GitHub::Turboscan.expects(:eval_ref_update_rules).returns(response)

    rule_runs = @rule.evaluate(context, pr_ref_update, rule_configs)
    assert_equal rule_configs.size, rule_runs.size
    rule_runs.each do |rule_run|
      assert_equal "failed", rule_run.result
      assert_equal "Could not check code scanning status.", rule_run.message
    end
  end

  test "unavailable diff blocks the rule" do
    merge_commit = @repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first

    pull = PullRequest.create_for!(
      @repo,
      user: @user,
      base: "master",
      head: "cr-line-endings",
      title: "convert to CR line ending"
    )

    pr_ref_update = Git::Branch::Update.new(
      repository: @repo,
      refname: "refs/heads/#{pull.base_ref_name}",
      before_oid:  merge_commit.parent_oids.first,
      after_oid: merge_commit.oid,
      pull_request: pull
    )

    context = RuleEngine::RuleEvaluationContext.new(@repo, additional_context: { merge_box_evaluation: true })
    rule_config = build(
      :repository_rule_configuration,
      rule_type: "code_scanning",
      parameters: {
        code_scanning_tools: [
          { tool: "CodeQL", alerts_threshold: RuleEngine::Rules::CodeScanningRule::SEVERITY_NONE, security_alerts_threshold: RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_NONE },
        ],
      }
    )

    assert_empty rule_config.parameter_errors

    GitHub.flipper.enable(:code_scanning_rule_diff_failure_handling)

    # Diff is not available
    GitHub::Diff.any_instance.stubs(:unavailable_reason).returns("corrupt")
    refute pr_ref_update.diff.available?
    refute pr_ref_update.diff.truncated?

    # No cassette needed here because when diff is not available Turboscan will not be called
    rule_run, = @rule.evaluate(context, pr_ref_update, [rule_config])
    assert_equal "failed", rule_run.result, rule_run.message

    # When FF is disabled
    GitHub.flipper.disable(:code_scanning_rule_diff_failure_handling)
    @repo.disable_feature(:code_scanning_rule_diff_failure_handling) # Needed to clear memoized state
    VCR.use_cassette("code-scanning/eval-ref-update-rules-pass1", persist_with: :turboscan) do
      rule_run, = @rule.evaluate(context, pr_ref_update, [rule_config])
      assert_equal "allowed", rule_run.result, rule_run.message
    end
  end

  test "truncated diff gives an extended failure message when alerts are found" do
    merge_commit = @repo.commits.create_merge_commit(@user, "master", "cr-line-endings").first

    pull = PullRequest.create_for!(
      @repo,
      user: @user,
      base: "master",
      head: "cr-line-endings",
      title: "convert to CR line ending"
    )

    pr_ref_update = Git::Branch::Update.new(
      repository: @repo,
      refname: "refs/heads/#{pull.base_ref_name}",
      before_oid:  merge_commit.parent_oids.first,
      after_oid: merge_commit.oid,
      pull_request: pull
    )

    context = RuleEngine::RuleEvaluationContext.new(@repo, additional_context: { merge_box_evaluation: true })
    rule_config = build(
      :repository_rule_configuration,
      rule_type: "code_scanning",
      parameters: {
        code_scanning_tools: [
          { tool: "CodeQL", alerts_threshold: RuleEngine::Rules::CodeScanningRule::SEVERITY_NONE, security_alerts_threshold: RuleEngine::Rules::CodeScanningRule::SECURITY_SEVERITY_NONE },
        ],
      }
    )

    assert_empty rule_config.parameter_errors

    GitHub.flipper.enable(:code_scanning_rule_diff_failure_handling)

    # Diff is truncated but rule passes
    GitHub::Diff.any_instance.stubs(:truncated?).returns(true)
    GitHub::Diff.any_instance.stubs(:truncated_reason).returns("maximum file count exceeded: total=1234")
    assert pr_ref_update.diff.available?
    assert pr_ref_update.diff.truncated?
    VCR.use_cassette("code-scanning/eval-ref-update-rules-pass1", persist_with: :turboscan) do
      rule_run, = @rule.evaluate(context, pr_ref_update, [rule_config])
      assert_equal "allowed", rule_run.result, rule_run.message
    end

    # Diff is truncated but rule fails
    VCR.use_cassette("code-scanning/eval-ref-update-rules-fail1", persist_with: :turboscan) do
      rule_run, = @rule.evaluate(context, pr_ref_update, [rule_config])
      assert_equal "failed", rule_run.result
      assert_includes rule_run.message, "because the code changes were too large"
    end

    # When FF is disabled
    GitHub.flipper.disable(:code_scanning_rule_diff_failure_handling)
    @repo.disable_feature(:code_scanning_rule_diff_failure_handling) # Needed to clear memoized state
    VCR.use_cassette("code-scanning/eval-ref-update-rules-fail1", persist_with: :turboscan) do
      rule_run, = @rule.evaluate(context, pr_ref_update, [rule_config])
      assert_equal "failed", rule_run.result
      refute_includes rule_run.message, "because the code changes were too large"
    end
  end
end
