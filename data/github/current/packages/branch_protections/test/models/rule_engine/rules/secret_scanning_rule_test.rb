# typed: true
# frozen_string_literal: true

require "test_helper"

class RuleEngineSecretScanningRuleTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include SecretScanning::Features::FeatureFlagHelper
  include SecretScanning::Constants

  fixtures do
    @repo = create(:repository)
    @user = create(:user)
    @reviewer = create(:user)
    @repo.add_member(@reviewer)
  end

  setup do
    @ref_updates = [
      create_branch_update(@repo, name: "main"),
      create_branch_update(@repo, name: "develop"),
    ]
    @context = RuleEngine::RuleEvaluationContext.new(@repo, @user, additional_context: {
      commit_refs_evaluation: true
    })
    @rule_config = build(
      :repository_rule_configuration,
      rule_type: RuleEngine::Rules::SecretScanningRule::RULE_NAME,
      parameters: {}
    )
    @configs_by_ref_update = @ref_updates.each_with_object({}) do |ref_update, hash|
      hash[ref_update] = [@rule_config]
    end
    @rule = RuleEngine::Rules::SecretScanningRule.new
    SecretScanning::Services::DelegatedBypassService.stubs(:can_review_bypass_request?).with(@repo, @user).returns([false, ""])
    SecretScanning::Services::DelegatedBypassService.stubs(:can_review_bypass_request?).with(@repo, @reviewer).returns([true, ""])
  end

  test "rule is registered" do
    rule = RuleEngine::Evaluator.rule_impl_for_rule_type(RuleEngine::Rules::SecretScanningRule::RULE_NAME)
    refute_nil rule
    assert_equal RuleEngine::Rules::SecretScanningRule, rule.class
  end

  context "bulk_evaluate" do
    test "succeeds when no secrets are found" do
      scan_result = SecretScanning::Models::SynchronousScanResult.new(
        secrets: [],
        completed: true,
        num_secrets_found_over_limit: 0
      )
      SecretScanning::Services::PushProtectionService.expects(:scan_ref_updates).with(@ref_updates, @repo, @user, push_state: nil, delegated_bypass_enabled: false).returns(scan_result)
      rule_runs = @rule.bulk_evaluate(@context, @configs_by_ref_update)
      assert_equal 2, rule_runs.size

      assert_predicate rule_runs[0], :allowed?
      assert_predicate rule_runs[1], :allowed?
    end

    test "succeeds when no secrets are found even when the scan is incomplete" do
      scan_result = SecretScanning::Models::SynchronousScanResult.new(
        secrets: [],
        # scan is incomplete
        completed: false,
        num_secrets_found_over_limit: 0
      )
      SecretScanning::Services::PushProtectionService.expects(:scan_ref_updates).with(@ref_updates, @repo, @user, push_state: nil, delegated_bypass_enabled: false).returns(scan_result)
      rule_runs = @rule.bulk_evaluate(@context, @configs_by_ref_update)
      assert_equal 2, rule_runs.size

      assert_predicate rule_runs[0], :allowed?
      assert_predicate rule_runs[1], :allowed?
    end

    test "when the scan succeeds + delegated bypass requests were used, marks those requests as completed" do
      # Create 2 exemption requests to mark as used in the push protection scan
      rulesuite = RuleEngine::RuleSuite.new(repository: @repo, ref_name: @ref_updates[0].refname, before_oid: @ref_updates[0].before_oid, after_oid: @ref_updates[1].after_oid, actor: @user)
      used_exemption_requests = %w[ksuid123 ksuid456].map do |resource_id|
        Exemptions::Public.create_request(resource_owner: rulesuite, requester: @user, resource_identifier: resource_id, repository: @repo, request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE, requester_comment: "a comment", expires_at: Time.now + 1.day)
      end
      scan_result = SecretScanning::Models::SynchronousScanResult.new(
        secrets: [],
        completed: true,
        num_secrets_found_over_limit: 0,
        used_delegated_bypass_request_ids: used_exemption_requests.map { |request| T.must(request.id) }
      )
      SecretScanning::Services::PushProtectionService.expects(:scan_ref_updates).with(@ref_updates, @repo, @user, push_state: nil, delegated_bypass_enabled: false).returns(scan_result)
      rule_runs = @rule.bulk_evaluate(@context, @configs_by_ref_update)
      assert_equal 2, rule_runs.size

      assert_predicate rule_runs[0], :allowed?
      assert_predicate rule_runs[1], :allowed?

      # Check the status of the exemption requests
      used_exemption_requests.each do |request|
        assert_equal "completed", request.reload.status
      end
    end

    test "for a delegated bypass enabled repo, initiates scan with self-approval flow if push actor is reviewer" do
      SecretScanning::Features::Repo::DelegatedBypass.any_instance.stubs(:enabled?).returns(true)
      scan_result = SecretScanning::Models::SynchronousScanResult.new(
        secrets: [],
        completed: true,
        num_secrets_found_over_limit: 0
      )
      SecretScanning::Services::PushProtectionService.expects(:scan_ref_updates).with(@ref_updates, @repo, @reviewer, push_state: nil, delegated_bypass_enabled: false).returns(scan_result)
      rule_runs = @rule.bulk_evaluate(RuleEngine::RuleEvaluationContext.new(@repo, @reviewer, additional_context: {
        commit_refs_evaluation: true
      }), @configs_by_ref_update)
      assert_equal 2, rule_runs.size

      assert_predicate rule_runs[0], :allowed?
      assert_predicate rule_runs[1], :allowed?
    end

    test "fails when secrets are found" do
      secrets = [
        SecretScanning::Models::Secret.new(
          type: "GITHUB_TOKEN_V2",
          fingerprint: "abcd1234",
          token_metadata: SecretScanning::Models::TokenMetadata.new(
            token_type: "GITHUB_TOKEN_V2",
            label: "GitHub Personal Access Token",
            slug: "github_token_v2",
            provider: "GitHub",
          ),
          bypass_placeholder_ksuid: "1",
          locations: [
            SecretScanning::Models::Location.new(
              commit_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c26",
              path: "foo/bar.txt",
              start_line: 1,
            )
          ]
        )
      ]

      scan_result = SecretScanning::Models::SynchronousScanResult.new(secrets: secrets, completed: true)
      SecretScanning::Services::PushProtectionService.expects(:scan_ref_updates).with(@ref_updates, @repo, @user, push_state: nil, delegated_bypass_enabled: false).returns(scan_result)

      rule_runs = @rule.bulk_evaluate(@context, @configs_by_ref_update)
      assert_equal 2, rule_runs.size

      refute_predicate rule_runs[0], :allowed?
      refute_predicate rule_runs[1], :allowed?

      # Both descriptions should be the short message
      assert_equal rule_runs[0]&.message, "Push cannot contain secrets"
      assert_equal rule_runs[1]&.message, "Push cannot contain secrets"

      # There should be no CLI message, but that gets constructed in SecretScanningProvider#on_evaluation_complete.
      assert_nil rule_runs[0]&.cli_message
      assert_nil rule_runs[1]&.cli_message

      # We should store the scan result in the rule runs' evaluation metadata, so that it's accessible from
      # SecretScanningProvider#on_evaluation_complete.
      assert_equal rule_runs[0]&.evaluation_metadata[RULE_RUN_SCAN_RESULT_METADATA_KEY], scan_result.as_json
      assert_equal rule_runs[1]&.evaluation_metadata[RULE_RUN_SCAN_RESULT_METADATA_KEY], scan_result.as_json
    end

    test "succeeds (i.e doesn't do anything) when context.actor is not a user " do
      public_key = PublicKey.new(key: "1234")
      context_with_public_key = RuleEngine::RuleEvaluationContext.new(@repo, public_key)
      rule_runs = @rule.bulk_evaluate(@context, @configs_by_ref_update)
      assert_equal 2, rule_runs.size
      assert_predicate rule_runs[0], :allowed?
      assert_predicate rule_runs[1], :allowed?
    end

  end


  context "skip_evaluation?" do
    test "rule only runs for commit refs" do
      context = RuleEngine::RuleEvaluationContext.new(@repo, @user, additional_context: {
        commit_refs_evaluation: false
      })
      assert @rule.skip_evaluation?(context, @rule_config)
    end

    test "rule doesn't run without an actor" do
      context = RuleEngine::RuleEvaluationContext.new(@repo, nil, additional_context: {
        commit_refs_evaluation: true
      })
      assert @rule.skip_evaluation?(context, @rule_config)
    end

    test "happy path" do
      context = RuleEngine::RuleEvaluationContext.new(@repo, @user, additional_context: {
        commit_refs_evaluation: true
      })
      refute @rule.skip_evaluation?(context, @rule_config)
    end
  end

  context "insights_ui_metadata" do
    test "returns scan result metadata if exists" do
      secrets = [
        SecretScanning::Models::Secret.new(
          type: "GITHUB_TOKEN_V2",
          fingerprint: "abcd1234",
          token_metadata: SecretScanning::Models::TokenMetadata.new(
            token_type: "GITHUB_TOKEN_V2",
            label: "GitHub Personal Access Token",
            slug: "github_token_v2",
            provider: "GitHub",
          ),
          bypass_placeholder_ksuid: "1",
          locations: [
            SecretScanning::Models::Location.new(
              commit_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c26",
              path: "foo/bar.txt",
              start_line: 1,
            )
          ]
        )
      ]

      scan_result = SecretScanning::Models::SynchronousScanResult.new(secrets: secrets, completed: true)
      evaluation_metadata = { RULE_RUN_SCAN_RESULT_METADATA_KEY => scan_result }
      rule_run = RuleEngine::RuleRun.failure(rule_config: @rule_config, ref_update: @ref_updates[0], message: "message", evaluation_metadata: evaluation_metadata)
      result = @rule.insights_ui_metadata(rule_run)
      assert_equal result, scan_result.as_json
    end

    test "returns content scan result metadata if exists" do
      secrets = [
        SecretScanning::Models::Secret.new(
          type: "GITHUB_TOKEN_V2",
          fingerprint: "abcd1234",
          token_metadata: SecretScanning::Models::TokenMetadata.new(
            token_type: "GITHUB_TOKEN_V2",
            label: "GitHub Personal Access Token",
            slug: "github_token_v2",
            provider: "GitHub",
          ),
          bypass_placeholder_ksuid: "1",
          locations: [
            SecretScanning::Models::Location.new(
              commit_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c26",
              path: "foo/bar.txt",
              start_line: 1,
            )
          ]
        )
      ]

      scan_result = SecretScanning::Models::SynchronousScanResult.new(secrets: secrets, completed: true)
      path = "/home/README.md"
      evaluation_metadata = { RULE_RUN_SCAN_RESULT_METADATA_KEY => { path => scan_result } }
      rule_run = RuleEngine::RuleRun.failure(rule_config: @rule_config, ref_update: @ref_updates[0], message: "message", evaluation_metadata: evaluation_metadata)
      result = @rule.insights_ui_metadata(rule_run)
      assert_equal result, {
        path => scan_result.as_json
      }
    end

    test "returns nil if scan result metadata doesn't exist" do
      assert_nil @rule.insights_ui_metadata(RuleEngine::RuleRun.failure(rule_config: @rule_config, ref_update: @ref_updates[0], message: "message", evaluation_metadata: {}))
    end
  end
end
