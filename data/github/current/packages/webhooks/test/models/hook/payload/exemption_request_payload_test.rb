# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadExemptionRequestPayloadTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    GitHub.flipper[:push_rulesets].enable
    GitHub.flipper[:push_ruleset_delegated_bypass].enable
    GitHub.flipper[:exemption_request_webhooks].enable

    @org_admin = create(:user)
    @org = create(:business_plus_organization, name: "org", admin: @org_admin)
    @org_repo = create(:private_repository, owner: @org, from_example: :simple)
    @org_member = create(:user)
    @org.add_member(@org_member)
    @org_repo.add_member(@org_member, action: :write)

    @repo_hook = create :hook, installation_target: @org_repo, events: %w(exemption_request_push_ruleset exemption_request_secret_scanning)
    @org_hook = create :hook, installation_target: @org, events: %w(exemption_request_push_ruleset exemption_request_secret_scanning)

    @push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    config = create(:repository_rule_configuration, repository_ruleset: @push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })

    metadata = {
      message: "Create a file",
      author_email: @org_member.email,
      committer_email: @org_member.email,
      blobs: {
        "some-long-file-name" => "contents"
      },
    }

    @suite = RuleEngine::Evaluator.evaluate_pre_commit_rules(@org_repo, @org_repo.heads["master"].target_oid, @org_member, metadata, target_ref_name: "master")
  end

  ACTION_TO_STATUS = {
    created: "pending",
    cancelled: "cancelled",
    completed: "completed"
  }.with_indifferent_access.freeze

  # Iterate through integration tests for each request type
  # While the instrumentation is the same and is called from the ExemptionRequest class
  # we have independent hook events for each request type
  ["push_ruleset_bypass", SecretScanning::Constants::EXEMPTION_REQUEST_TYPE].each do |request_type|
    %w(created cancelled completed).each do |status|
      test "#{request_type} includes exemption request status '#{status}' without a response" do
        exemption_request(request_type:).status = status unless status == "created"
        exemption_request(request_type:).save!
        event = hook_event(request_type:).new(action: status, exemption_request_id: exemption_request(request_type:).id)

        payload = hook_payload(request_type:).new(event).to_hash

        refute_nil payload[:exemption_request]
        assert payload[:repository]
        assert payload[:organization]
        # Explicity check the expected keys to ensure we aren't exposing anything we shouldn't
        keys = %i[id number repository_id requester_id requester_login request_type status requester_comment metadata expires_at created_at responses exemption_request_data html_url]
        assert_same_elements(keys, payload[:exemption_request].keys)
        assert_same_hash Api::Serializer.serialize(:exemption_request_hash, exemption_request(request_type:)), payload[:exemption_request]
        assert_equal exemption_request(request_type:).id, payload[:exemption_request][:id]
        assert_equal ACTION_TO_STATUS[status], payload[:exemption_request][:status]
        # Actor is requester
        assert_equal exemption_request(request_type:).requester_id, payload[:sender][:id]
        assert_nil payload[:exemption_response]
      end
    end

    %w(approved rejected dismissed).each do |status|
      test "#{request_type} includes exemption response status '#{status}'" do
        if request_type == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE
          SecretScanning::Services::DelegatedBypassService.expects(:can_review_bypass_request?).with(@org_repo, @org_admin).returns(true)
        end
        exemption_request(request_type:).save!
        exemption_response(request_type:).status = status
        exemption_response(request_type:).save!

        action = status == "dismissed" ? :response_dismissed : :response_submitted

        # Get updated exemption request, which has responses
        exemption_request(request_type:).reload

        event = hook_event(request_type:).new(action:, exemption_request_id: exemption_request(request_type:).id, exemption_response_id: exemption_response(request_type:).id)

        payload = hook_payload(request_type:).new(event).to_hash

        refute_nil payload[:exemption_request]
        refute_nil payload[:exemption_response]
        assert payload[:repository]
        assert payload[:organization]
        # Explicity check the expected keys to ensure we aren't exposing anything we shouldn't
        request_keys = %i[id number repository_id requester_id requester_login request_type status requester_comment metadata expires_at created_at responses exemption_request_data html_url]
        assert_same_elements(request_keys, payload[:exemption_request].keys)
        response_keys = %i[id reviewer_id reviewer_login status created_at]
        assert_same_elements(response_keys, payload[:exemption_response].keys)
        assert_same_hash Api::Serializer.serialize(:exemption_request_hash, exemption_request(request_type:)), payload[:exemption_request]
        assert_same_hash Api::Serializer.serialize(:exemption_response_hash, exemption_response(request_type:)), payload[:exemption_response]
        assert_equal exemption_response(request_type:).id, payload[:exemption_response][:id]
        assert_equal exemption_request(request_type:).id, payload[:exemption_request][:id]
        assert_equal status, payload[:exemption_response][:status]
        if status == "rejected"
          # Rejection response results in a rejected exemption request status
          assert_equal "rejected", payload[:exemption_request][:status]
        else
          # Everything else is pending until completion
          assert_equal "pending", payload[:exemption_request][:status]
        end
        # Actor is reviewer
        assert_equal exemption_response(request_type:).reviewer_id, payload[:sender][:id]
      end
    end

    test "#{request_type} exemption request includes previous responses" do
      # Create another reviewer
      another_reviewer = create(:user)
      @org.add_member(another_reviewer, action: :admin)
      if request_type == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE
        SecretScanning::Services::DelegatedBypassService.expects(:can_review_bypass_request?).with(@org_repo, @org_admin).returns(true)
        SecretScanning::Services::DelegatedBypassService.expects(:can_review_bypass_request?).with(@org_repo, another_reviewer).returns(true)
      end
      exemption_request(request_type:).save!
      exemption_response(request_type:).status = :approved
      exemption_response(request_type:).save!


      # Create another response
      another_response = exemption_response(request_type:).dup
      another_response.reviewer = another_reviewer
      another_response.status = :rejected
      another_response.save!

      # Get updated exemption request, which has responses
      exemption_request(request_type:).reload

      event = hook_event(request_type:).new(action: :response_submitted, exemption_request_id: exemption_request(request_type:).id, exemption_response_id: another_response.id)

      payload = hook_payload(request_type:).new(event).to_hash

      # Responses within request contain both responses
      assert_same_elements [exemption_response(request_type:).id, another_response.id], payload[:exemption_request][:responses].map { |r| r[:id] }
      assert_equal another_response.id, payload[:exemption_response][:id]
      assert_equal "rejected", payload[:exemption_request][:status]
      # Actor is reviewer
      assert_equal another_reviewer.id, payload[:sender][:id]
    end
  end

  context "when exemption request is push ruleset bypass" do
    test "contains an array of violations" do
      exemption_request(request_type: "push_ruleset_bypass").save!
      event = Hook::Event::ExemptionRequestPushRulesetEvent.new(action: :created, exemption_request_id: exemption_request(request_type: "push_ruleset_bypass").id)

      payload = Hook::Payload::ExemptionRequestPushRulesetPayload.new(event).to_hash

      refute_nil payload[:exemption_request][:exemption_request_data]
      assert_equal "push_ruleset_bypass", payload[:exemption_request][:exemption_request_data][:type]
      data = payload[:exemption_request][:exemption_request_data][:data]
      assert_equal 1, data.size

      rule_run = @suite.rule_runs.first

      assert_same_hash(
        {
          ruleset_id: @push_ruleset.id,
          ruleset_name: @push_ruleset.name,
          total_violations: rule_run.violations["total"],
          rule_type: rule_run.rule_impl.display_name
        }, payload[:exemption_request][:exemption_request_data][:data].first)

      # Only return expected metadata
      assert_nil payload[:exemption_request][:metadata]
    end
  end

  context "secret scanning" do
    test "CLI push contains an array of secrets" do
      # -- Start of secret scanning failure setup --- #
      filepath = "foo/bar.txt"
      secret_scanning_rule_config = build(
        :repository_rule_configuration,
        rule_type: RuleEngine::Rules::SecretScanningRule::RULE_NAME,
        parameters: {}
      )
      ref_update = create_branch_update(@org_repo, name: "main")
      rule = RuleEngine::Rules::SecretScanningRule.new
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
          bypass_placeholder_ksuid: "ksuid",
          locations: [
            SecretScanning::Models::Location.new(
              commit_oid: "4f82b923b9b73ac1a644f25ad8786a55202b5c26",
              path: filepath,
              start_line: 1,
              start_line_byte_position: 1,
            )
          ]
        )
      ]

      scan_result = SecretScanning::Models::SynchronousScanResult.new(secrets: secrets, completed: true)
      evaluation_metadata = { SecretScanning::Constants::RULE_RUN_SCAN_RESULT_METADATA_KEY => scan_result }
      rule_run = RuleEngine::RuleRun.failure(rule_config: secret_scanning_rule_config, ref_update: ref_update, message: "message", evaluation_metadata: evaluation_metadata)
      rule_suite = RuleEngine::RuleSuite.create!(actor: @org_member, rule_runs: [rule_run], repository: @org_repo, ref_update: ref_update)
      secret_scanning_exemption_request = Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: "ksuid",
        repository: @org_repo,
        request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
        requester_comment: "a comment",
        metadata: {
          label: "GitHub Personal Access Token",
          reason: "false_positive",
        }
      )
      # --- End of secret scanning failure setup --- #

      event = Hook::Event::ExemptionRequestSecretScanningEvent.new(action: :created, exemption_request_id: secret_scanning_exemption_request.id)

      payload = Hook::Payload::ExemptionRequestSecretScanningPayload.new(event).to_hash
      refute_nil payload[:exemption_request][:exemption_request_data]
      assert_equal SecretScanning::Constants::EXEMPTION_REQUEST_TYPE, payload[:exemption_request][:exemption_request_data][:type]
      data = payload[:exemption_request][:exemption_request_data][:data]
      assert_equal 1, data.size
      assert_same_hash(
        {
          secret_type: "GitHub Personal Access Token",
          locations: [{
            branch: rule_suite.ref_name,
            commit: "4f82b923b9b73ac1a644f25ad8786a55202b5c26",
            path: "#{filepath}:1:1",
          }]
        }, payload[:exemption_request][:exemption_request_data][:data].first)

      # Only return expected metadata
      assert_same_elements(%w[label reason], payload[:exemption_request][:metadata].keys)
      assert_same_hash(
        {
          label: "GitHub Personal Access Token",
          reason: "false_positive",
        }.with_indifferent_access, payload[:exemption_request][:metadata])
    end

    test "web push contains an array of secrets" do
      # -- Start of secret scanning failure setup --- #
      filepath = "foo/bar.txt"
      secret_scanning_rule_config = build(
        :repository_rule_configuration,
        rule_type: RuleEngine::Rules::SecretScanningRule::RULE_NAME,
        parameters: {}
      )
      ref_update = create_branch_update(@org_repo, name: "main")
      rule = RuleEngine::Rules::SecretScanningContentScanRule.new
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
          bypass_placeholder_ksuid: "ksuid",
          locations: [
            SecretScanning::Models::Location.new(
              commit_oid: "PENDING",
              path: filepath,
              start_line: 1,
              start_line_byte_position: 1,
            )
          ]
        )
      ]

      scan_results = { filepath => SecretScanning::Models::SynchronousScanResult.new(secrets: secrets, completed: true) }
      evaluation_metadata = { SecretScanning::Constants::CONTENT_RULE_RUN_SCAN_RESULT_METADATA_KEY => scan_results }
      rule_run = RuleEngine::RuleRun.failure(rule_config: secret_scanning_rule_config, ref_update: ref_update, message: "message", evaluation_metadata: evaluation_metadata)
      rule_suite = RuleEngine::RuleSuite.create!(actor: @org_member, rule_runs: [rule_run], repository: @org_repo, ref_update: ref_update)
      secret_scanning_exemption_request = Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: @org_member,
        resource_identifier: "ksuid",
        repository: @org_repo,
        request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
        requester_comment: "a comment",
        metadata: {
          label: "GitHub Personal Access Token",
          reason: "false_positive",
        }
      )
      # --- End of secret scanning failure setup --- #

      event = Hook::Event::ExemptionRequestSecretScanningEvent.new(action: :created, exemption_request_id: secret_scanning_exemption_request.id)

      payload = Hook::Payload::ExemptionRequestSecretScanningPayload.new(event).to_hash
      refute_nil payload[:exemption_request][:exemption_request_data]
      assert_equal SecretScanning::Constants::EXEMPTION_REQUEST_TYPE, payload[:exemption_request][:exemption_request_data][:type]
      data = payload[:exemption_request][:exemption_request_data][:data]
      assert_equal 1, data.size
      assert_same_hash(
        {
          secret_type: "GitHub Personal Access Token",
          locations: [{
            branch: rule_suite.ref_name,
            commit: "Pending (from file editor)",
            path: "#{filepath}:1:1",
          }]
        }, payload[:exemption_request][:exemption_request_data][:data].first)

      # Only return expected metadata
      assert_same_elements(%w[label reason], payload[:exemption_request][:metadata].keys)
      assert_same_hash(
        {
          label: "GitHub Personal Access Token",
          reason: "false_positive",
        }.with_indifferent_access, payload[:exemption_request][:metadata])
    end
  end

  def exemption_request(request_type:)
    @exemption_request ||= Exemptions::ExemptionRequest.new(
      resource_owner: @suite,
      requester: @org_member,
      resource_identifier: @suite.after_oid,
      repository: @suite.repository,
      request_type:,
    )
  end

  def exemption_response(request_type:)
    @exemption_response ||= Exemptions::ExemptionResponse.new(
      reviewer: @org_admin,
      exemption_request: exemption_request(request_type:)
    )
  end

  def hook_event(request_type:)
    @hook_event ||= (
      if request_type == "push_ruleset_bypass"
        Hook::Event::ExemptionRequestPushRulesetEvent
      else
        Hook::Event::ExemptionRequestSecretScanningEvent
      end
    )
  end

  def hook_payload(request_type:)
    @hook_payload ||= (
      if request_type == "push_ruleset_bypass"
        Hook::Payload::ExemptionRequestPushRulesetPayload
      else
        Hook::Payload::ExemptionRequestSecretScanningPayload
      end
    )
  end
end
