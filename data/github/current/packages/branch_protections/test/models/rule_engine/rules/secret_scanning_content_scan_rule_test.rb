# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEngineSecretScanningContentScanRuleTest < GitHub::TestCase
  include RulesEngine::CandidateTestHelper

  fixtures do
    @repo = create(:repository)
    @actor = create(:user)

    @org = create(:organization)
    @repo_in_org = create(:repository, owner: @org)

    @business = create(:business)
    @org_in_business = create(:organization, business: @business)
    @repo_in_business_org = create(:repository, owner: @org_in_business)
  end

  setup do
    @context = RuleEngine::RuleEvaluationContext.new(@repo, @actor)
    @context_with_org = RuleEngine::RuleEvaluationContext.new(@repo_in_org, @actor)
    @context_with_business = RuleEngine::RuleEvaluationContext.new(@repo_in_business_org, @actor)

    @ref_update = create_branch_update(@repo, name: "main")
    @ref_update_on_org_repo = create_branch_update(@repo_in_org, name: "main")
    @ref_update_on_business_org_repo = create_branch_update(@repo_in_business_org, name: "main")

    @rule_config = build(
      :repository_rule_configuration,
      rule_type: RuleEngine::Rules::SecretScanningContentScanRule::RULE_NAME,
      parameters: {}
    )

    @rule = T.let(RuleEngine::Rules::SecretScanningContentScanRule.new, RuleEngine::Rules::SecretScanningContentScanRule)
  end

  test "rule is registered" do
    rule = RuleEngine::Evaluator.rule_impl_for_rule_type(RuleEngine::Rules::SecretScanningContentScanRule::RULE_NAME)
    refute_nil rule
    assert_equal RuleEngine::Rules::SecretScanningContentScanRule, rule.class
  end

  test "fails if candidate contains a secret" do
    resp = SecretScanning::Models::SynchronousScanResult.new(completed: true, secrets: [SecretScanning::Models::Secret.new(type: "GITHUB_TOKEN_V2", fingerprint: "abcd1234")])
    SecretScanning::Services::PushProtectionService.expects(:scan_content).returns(resp)

    candidate = create_blob_candidate
    rule_runs = @rule.bulk_evaluate_candidates(@context, @ref_update, [@rule_config], [candidate])

    assert_equal 1, rule_runs.size
    run = T.let(T.must(rule_runs.keys[0]), RepositoryRuleConfiguration)
    assert_equal run.rule_type, RuleEngine::Rules::SecretScanningContentScanRule::RULE_NAME
    assert_equal 1, T.must(rule_runs[run]).size
    result = T.must(T.must(rule_runs[run])[0])
    refute result.success?
    refute_nil result.metadata
    scan_result = T.cast(result.metadata, SecretScanning::Models::SynchronousScanResult)
    assert_equal 1, scan_result.secrets.size
    assert_equal "GITHUB_TOKEN_V2", scan_result.secrets[0]&.type
  end

  test "succeeds if no secrets are found" do
    resp = SecretScanning::Models::SynchronousScanResult.new(completed: true, secrets: [])
    SecretScanning::Services::PushProtectionService.expects(:scan_content).returns(resp)

    candidates = [create_blob_candidate]
    rule_runs = @rule.bulk_evaluate_candidates(@context, @ref_update, [@rule_config], candidates)

    assert_equal 1, rule_runs.size
    run = T.let(T.must(rule_runs.keys[0]), RepositoryRuleConfiguration)
    assert_equal run.rule_type, RuleEngine::Rules::SecretScanningContentScanRule::RULE_NAME
    assert_equal 1, T.must(rule_runs[run]).size
    result = T.must(T.must(rule_runs[run])[0])
    assert result.success?
  end

  test "succeeds if path is missing" do
    candidates = [create_blob_candidate(path: "")]
    rule_runs = @rule.bulk_evaluate_candidates(@context, @ref_update, [@rule_config], candidates)

    assert_equal 1, rule_runs.size
    run = T.let(T.must(rule_runs.keys[0]), RepositoryRuleConfiguration)
    assert_equal run.rule_type, RuleEngine::Rules::SecretScanningContentScanRule::RULE_NAME
    assert_equal 1, T.must(rule_runs[run]).size
    result = T.must(T.must(rule_runs[run])[0])
    assert result.success?
  end

  test "fails if path is missing and request came from blob evaluation" do
    resp = SecretScanning::Models::SynchronousScanResult.new(completed: true, secrets: [SecretScanning::Models::Secret.new(type: "GITHUB_TOKEN_V2", fingerprint: "abcd1234")])
    SecretScanning::Services::PushProtectionService.expects(:scan_content).returns(resp)

    context = RuleEngine::RuleEvaluationContext.new(@repo, @actor, additional_context: { blob_evaluation: true })
    candidates = [create_blob_candidate(path: "")]
    rule_runs = @rule.bulk_evaluate_candidates(context, @ref_update, [@rule_config], candidates)

    assert_equal 1, rule_runs.size
    run = T.let(T.must(rule_runs.keys[0]), RepositoryRuleConfiguration)
    assert_equal run.rule_type, RuleEngine::Rules::SecretScanningContentScanRule::RULE_NAME
    assert_equal 1, T.must(rule_runs[run]).size
    result = T.must(T.must(rule_runs[run])[0])
    refute result.success?
    refute_nil result.metadata
    scan_result = T.cast(result.metadata, SecretScanning::Models::SynchronousScanResult)
    assert_equal 1, scan_result.secrets.size
    assert_equal "GITHUB_TOKEN_V2", scan_result.secrets[0]&.type
  end

  test "generates allowed rule run when no violations" do
    result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, [])

    assert result.allowed?
  end

  test "generates failed rule run with scan result when violations exist" do
    expected_scan_result1 = SecretScanning::Models::SynchronousScanResult.new(completed: true, secrets: [SecretScanning::Models::Secret.new(type: "GITHUB_TOKEN_V2", fingerprint: "abcd1234", bypass_placeholder_ksuid: "ksuid123")])
    expected_scan_result2 = SecretScanning::Models::SynchronousScanResult.new(completed: true, secrets: [SecretScanning::Models::Secret.new(type: "CLOJARS_DEPLOY_TOKEN", fingerprint: "abcd4567", bypass_placeholder_ksuid: "ksuid456")])
    violations = [
      RuleEngine::Violation.new(candidate: create_blob_candidate(path: "path/to/file1.txt"), metadata: expected_scan_result1),
      RuleEngine::Violation.new(candidate: create_blob_candidate(path: "path/to/file2.txt"), metadata: expected_scan_result2)
    ]

    result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, violations)
    assert result.failed?
    scan_results = result.evaluation_metadata[SecretScanning::Constants::CONTENT_RULE_RUN_SCAN_RESULT_METADATA_KEY]
    refute_nil scan_results

    # scan results are returned in a hash as file path => scan result
    assert scan_results.key?("path/to/file1.txt")
    assert scan_results.key?("path/to/file2.txt")

    actual_scan_result1 = SecretScanning::Models::SynchronousScanResult.from_hash(scan_results["path/to/file1.txt"])
    assert actual_scan_result1.completed
    assert_equal 1, actual_scan_result1.secrets.size
    assert_equal "GITHUB_TOKEN_V2", actual_scan_result1.secrets[0]&.type
    assert_equal "ksuid123", actual_scan_result1.secrets[0]&.bypass_placeholder_ksuid

    actual_scan_result2 = SecretScanning::Models::SynchronousScanResult.from_hash(scan_results["path/to/file2.txt"])
    assert actual_scan_result2.completed
    assert_equal 1, actual_scan_result2.secrets.size
    assert_equal "CLOJARS_DEPLOY_TOKEN", actual_scan_result2.secrets[0]&.type
    assert_equal "ksuid456", actual_scan_result2.secrets[0]&.bypass_placeholder_ksuid
  end

  test "failed scan should return metadata" do
    metadata = SecretScanning::Models::SynchronousScanResult.new(
      secrets: [SecretScanning::Models::Secret.new(type: "GITHUB_TOKEN_V2", fingerprint: "abcd1234", bypass_placeholder_ksuid: "ksuid123")],
    )
    violations = [RuleEngine::Violation.new(candidate: create_blob_candidate, metadata: metadata)]

    result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, violations)
    assert result.failed?

    result = result.evaluation_metadata[SecretScanning::Constants::CONTENT_RULE_RUN_SCAN_RESULT_METADATA_KEY]

    assert_equal 1, result.size
    assert_equal "ksuid123", result["README.md"]["secrets"][0]["bypass_placeholder_ksuid"]
  end

  test "failed scan message should return message" do
    violations = [RuleEngine::Violation.new(candidate: create_blob_candidate)]

    result = @rule.generate_evaluation_result(@context, @ref_update, @rule_config, violations)
    assert result.failed?

    assert_equal result.message, "Secret detected in content"
  end

  test "failed scan message should return a custom resource from organization" do
    violations = [RuleEngine::Violation.new(candidate: create_blob_candidate)]

    resource = "https://example.com/test.txt"
    @org.set_push_protection_custom_message(resource, @actor)
    SecretScanning::Features::Org::PushProtection.any_instance.stubs(:custom_message_enabled?).returns(true)

    result = @rule.generate_evaluation_result(@context_with_org, @ref_update_on_org_repo, @rule_config, violations)
    assert result.failed?

    assert_equal result.message, "Secret detected in content. Review a resource from your organization, #{@org.name}: #{resource}"
  end

  test "failed scan message should return a custom resource from business" do
    violations = [RuleEngine::Violation.new(candidate: create_blob_candidate)]

    resource = "https://example.com/testbusiness.txt"
    @business.set_push_protection_custom_message(resource, @actor)
    SecretScanning::Features::Business::PushProtection.any_instance.stubs(:custom_message_enabled?).returns(true)

    result = @rule.generate_evaluation_result(@context_with_business, @ref_update_on_business_org_repo, @rule_config, violations)
    assert result.failed?

    assert_equal result.message, "Secret detected in content. Review a resource from your enterprise, #{@business.name}: #{resource}"
  end

  test "when the scan succeeds + delegated bypass requests were used, marks those requests as completed" do
    # Create 2 exemption requests to mark as used in the push protection scan
    rulesuite = RuleEngine::RuleSuite.new(repository: @repo, ref_name: @ref_update.refname, before_oid: @ref_update.before_oid, after_oid: @ref_update.after_oid, actor: @actor)
    used_exemption_requests = %w[ksuid123 ksuid456].map do |resource_id|
      Exemptions::Public.create_request(resource_owner: rulesuite, requester: @actor, resource_identifier: resource_id, repository: @repo, request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE, requester_comment: "a comment", expires_at: Time.now + 1.day)
    end
    scan_result = SecretScanning::Models::SynchronousScanResult.new(
      secrets: [],
      completed: true,
      num_secrets_found_over_limit: 0,
      used_delegated_bypass_request_ids: used_exemption_requests.map { |request| T.must(request.id) }
    )
    SecretScanning::Services::PushProtectionService.expects(:scan_content).returns(scan_result)

    candidates = [create_blob_candidate]
    rule_runs = @rule.bulk_evaluate_candidates(@context, @ref_update, [@rule_config], candidates)

    assert_equal 1, rule_runs.size
    run = T.let(T.must(rule_runs.keys[0]), RepositoryRuleConfiguration)
    assert_equal run.rule_type, RuleEngine::Rules::SecretScanningContentScanRule::RULE_NAME
    assert_equal 1, T.must(rule_runs[run]).size
    result = T.must(T.must(rule_runs[run])[0])
    assert result.success?

    # Check the status of the exemption requests
    used_exemption_requests.each do |request|
      assert_equal "completed", request.reload.status
    end
  end

  test "for a delegated bypass enabled repo, initiates scan with self-approval flow if push actor is reviewer" do
    SecretScanning::Services::DelegatedBypassService.stubs(:use_delegated_bypass_flow).returns(true)
    resp = SecretScanning::Models::SynchronousScanResult.new(
      secrets: [],
      completed: true,
      num_secrets_found_over_limit: 0
    )
    SecretScanning::Services::PushProtectionService.expects(:scan_content).with("Hello world", @repo, @actor, "README.md", delegated_bypass_enabled: true).returns(resp)

    candidates = [create_blob_candidate]
    rule_runs = @rule.bulk_evaluate_candidates(RuleEngine::RuleEvaluationContext.new(@repo, @actor, additional_context: {
      commit_refs_evaluation: true
    }), @ref_update, [@rule_config], candidates)

    assert_equal 1, rule_runs.size
    run = T.let(T.must(rule_runs.keys[0]), RepositoryRuleConfiguration)
    assert_equal run.rule_type, RuleEngine::Rules::SecretScanningContentScanRule::RULE_NAME
    assert_equal 1, T.must(rule_runs[run]).size
    result = T.must(T.must(rule_runs[run])[0])
    assert result.success?
  end

  context "skip_evaluation?" do
    test "does not run for commit refs" do
      context = RuleEngine::RuleEvaluationContext.new(@repo, @actor, additional_context: {
        commit_refs_evaluation: true
      })
      assert @rule.skip_evaluation?(context, @rule_config)
    end

    test "rule doesn't run without an actor" do
      context = RuleEngine::RuleEvaluationContext.new(@repo, nil, additional_context: {
        commit_refs_evaluation: false
      })
      assert @rule.skip_evaluation?(context, @rule_config)
    end

    test "happy path" do
      context = RuleEngine::RuleEvaluationContext.new(@repo, @actor, additional_context: {
        commit_refs_evaluation: false
      })
      refute @rule.skip_evaluation?(context, @rule_config)
    end
  end
end
