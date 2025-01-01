# typed: strict
# frozen_string_literal: true

require "test_helper"

class Exemptions::SerializerTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @org_admin = T.let(create(:user), T.nilable(User))
    @org = T.let(create(:business_plus_organization, name: "org1", admin: @org_admin), T.nilable(Organization))
    @org_member = T.let(create(:user), T.nilable(User))
    T.must(@org).add_member(@org_member)
    @org_repo = T.let(create(:private_repository, owner: @org), T.nilable(Repository))
  end

  setup do
    GitHub.flipper[:push_rulesets].enable
    GitHub.flipper[:push_ruleset_delegated_bypass].enable

    push_ruleset = create(
      :repository_ruleset,
      :org_admin_bypass_any,
      target: "push",
      source: @org_repo
    )
    config = create(
      :repository_rule_configuration,
      repository_ruleset: push_ruleset,
      rule_type: "max_file_path_length",
      parameters: {
        max_file_path_length: 10
      }
    )
    ref_update1 = create_branch_update(T.must(@org_repo), name: "main")
    run1 = RuleEngine::RuleRun.failure(rule_config: config, ref_update: ref_update1, message: "failed")
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update1, rule_runs: [run1], actor: T.must(@org_member))
    suite.save

    @request = T.let(Exemptions::ExemptionRequest.create!(
      resource_owner: suite,
      requester: @org_member,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type: "push_ruleset_bypass",
    ), T.nilable(Exemptions::ExemptionRequest))
    @response = T.let(Exemptions::ExemptionResponse.create!(
      exemption_request: @request,
      reviewer: @org_admin,
      status: :approved
    ), T.nilable(Exemptions::ExemptionResponse))

    # Get most recent request
    T.must(@request).reload
  end

  context "#request_to_hash" do
    test "return request for push ruleset bypass as hash" do
      @request = T.must(@request)
      request_hash = Exemptions::Serializer.request_to_hash(@request)

      assert_equal @request.id, request_hash[:id]
      assert_equal @request.number, request_hash[:number]
      assert_equal @request.repository_id, request_hash[:repository_id]
      assert_equal @request.requester_id, request_hash[:requester_id]
      assert_equal @request.request_type, request_hash[:request_type]
      assert_equal @request.resource_owner_id, request_hash[:resource_owner_id]
      assert_equal @request.resource_owner_type, request_hash[:resource_owner_type]
      assert_equal @request.resource_identifier, request_hash[:resource_identifier]
      assert_equal @request.status, request_hash[:status]
      assert_equal @request.expires_at, request_hash[:expires_at]
      assert_nil request_hash[:requester_comment]
      assert_nil request_hash[:metadata]
      assert_nil request_hash[:responses]
    end

    test "return request for push ruleset bypass with as hash with responses" do
      @request = T.must(@request)
      @response = T.must(@response)
      request_hash = Exemptions::Serializer.request_to_hash(@request, include_responses: true)

      assert_equal request_hash[:responses].count, 1
      assert_equal request_hash[:responses][0][:id], @response.id
      assert_equal request_hash[:responses][0][:reviewer_id], @response.reviewer_id
      assert_equal request_hash[:responses][0][:status], @response.status
    end

    context "#request_to_hash" do
      test "return response for push ruleset bypass as hash" do
        @response = T.must(@response)
        response_hash = Exemptions::Serializer.response_to_hash(@response)

        assert_equal response_hash[:id], @response.id
        assert_equal response_hash[:reviewer_id], @response.reviewer_id
        assert_equal response_hash[:status], @response.status
      end
    end
  end
end
