# typed: strict
# frozen_string_literal: true

require "test_helper"

class Exemptions::PublicTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper

  fixtures do
    @org_bypasser_1 = T.let(create(:user), T.nilable(User))
    @org = T.let(create(:business_plus_organization, name: "org1", admin: @org_bypasser_1), T.nilable(Organization))
    @org_member = T.let(create(:user), T.nilable(User))
    T.must(@org).add_member(@org_member)
    @org_bypasser_2 = T.let(create(:user), T.nilable(User))
    T.must(@org).add_member(@org_bypasser_2, action: :admin)
    @org_repo = T.let(create(:private_repository, owner: @org), T.nilable(Repository))
  end

  setup do
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
    @approved_response = T.let(Exemptions::ExemptionResponse.approve!(
      T.must(@request),
      T.must(@org_bypasser_2),
    ), T.nilable(Exemptions::ExemptionResponse))
  end

  context "#responses_for_repository" do
    test "return approved responses for a repo/actor" do
      @org_repo = T.must(@org_repo)
      @org_member = T.must(@org_member)
      @approved_response = T.must(@approved_response)

      approved_responses = Exemptions::Public.responses_for_repository(@org_repo.id, @org_member.id, "approved")

      assert_equal approved_responses.count, 1
      assert_equal T.must(approved_responses[0])[:id], @approved_response.id
    end

    test "return rejected responses for a repo/actor" do
      @org_repo = T.must(@org_repo)
      @org_member = T.must(@org_member)

      rejected_response = Exemptions::ExemptionResponse.reject!(
        T.must(@request),
        T.must(@org_bypasser_1),
      )

      rejected_responses = Exemptions::Public.responses_for_repository(@org_repo.id, @org_member.id, "rejected")

      assert_equal rejected_responses.count, 1
      assert_equal T.must(rejected_responses[0])[:id], rejected_response.id
    end

    test "return nothing if a request has 1 approval and 1 rejection and querying for approvals" do
      @org_repo = T.must(@org_repo)
      @org_member = T.must(@org_member)

      approved_responses = Exemptions::Public.responses_for_repository(@org_repo.id, @org_member.id, "approved")

      assert_equal approved_responses.count, 1

      rejected_response = Exemptions::ExemptionResponse.reject!(
        T.must(@request),
        T.must(@org_bypasser_1),
      )

      approved_responses = Exemptions::Public.responses_for_repository(@org_repo.id, @org_member.id, "approved")

      assert_equal approved_responses.count, 0
    end
  end

  context "#requests_for_repository" do
    test "return approved requests for a repo/actor" do
      @org_repo = T.must(@org_repo)
      @org_member = T.must(@org_member)
      @request = T.must(@request)

      approved_requests = Exemptions::Public.requests_for_repository(@org_repo.id, @org_member.id, "approved")

      assert_equal approved_requests.count, 1
      assert_equal T.must(approved_requests[0])[:id], @request.id
    end

    test "return rejected requests for a repo/actor" do
      @org_repo = T.must(@org_repo)
      @org_member = T.must(@org_member)
      @request = T.must(@request)

      rejected_response = Exemptions::ExemptionResponse.create!(
        exemption_request: @request,
        reviewer: T.must(@org_bypasser_1),
        status: :rejected
      )

      rejected_requests = Exemptions::Public.requests_for_repository(@org_repo.id, @org_member.id, "rejected")

      assert_equal rejected_requests.count, 1
      assert_equal T.must(rejected_requests[0])[:id], @request.id
    end

    test "return nothing if a request has 1 approval and 1 rejection and querying for approvals" do
      @org_repo = T.must(@org_repo)
      @org_member = T.must(@org_member)

      approved_requests = Exemptions::Public.requests_for_repository(@org_repo.id, @org_member.id, "approved")

      assert_equal approved_requests.count, 1

      rejected_response = Exemptions::ExemptionResponse.reject!(
        T.must(@request),
        T.must(@org_bypasser_1),
      )

      approved_requests = Exemptions::Public.requests_for_repository(@org_repo.id, @org_member.id, "approved")

      assert_equal approved_requests.count, 0
    end
  end
end
