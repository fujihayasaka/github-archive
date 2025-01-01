# typed: true
# frozen_string_literal: true

require "test_helper"

class ExemptionResponseTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include HydroTestHelpers

  fixtures do
    @org_admin = create(:user)
    @org = create(:business_plus_organization, name: "org1", admin: @org_admin)

    @org_member = create(:user)
    @org.add_member(@org_member)
    @org_repo = create(:private_repository, owner: @org)
    @org_repo.add_member(@org_member, action: :write)
    @org_repo.add_member(@org_admin, action: :admin)
  end

  setup do
    GitHub.flipper[:push_rulesets].enable
    GitHub.flipper[:push_ruleset_delegated_bypass].enable
  end

  test "allows saving valid review" do
    suite = create_suite

    request = Exemptions::ExemptionRequest.create!(
      resource_owner: suite,
      requester: @org_member,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type: "push_ruleset_bypass",
    )
    response = Exemptions::ExemptionResponse.new(
      exemption_request: request,
      reviewer: @org_admin,
      status: :approved
    )

    assert response.valid?
    assert response.save
  end

  test "does not allow saving invalid review" do
    suite = create_suite

    request = Exemptions::ExemptionRequest.create!(
      resource_owner: suite,
      requester: @org_member,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type: "push_ruleset_bypass",
    )
    # org_member cannot approve their own request
    response = Exemptions::ExemptionResponse.new(
      exemption_request: request,
      reviewer: @org_member,
      status: :approved
    )

    refute response.valid?
    refute response.save
  end

  test "rejecting review closes request as rejected, dismissing reverts request to pending" do
    suite = create_suite

    request = Exemptions::ExemptionRequest.create!(
      resource_owner: suite,
      requester: @org_member,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type: "push_ruleset_bypass",
    )
    response = Exemptions::ExemptionResponse.create!(
      exemption_request: request,
      reviewer: @org_admin,
      status: :rejected
    )
    request.reload

    assert request.rejected?

    response.status = :dismissed
    response.save!
    request.reload
    assert request.pending?
  end

  test "does not allow saving duplicates" do
    org_admin_2 = create(:user)
    @org.add_member(org_admin_2, action: :admin)
    @org_repo.add_member(org_admin_2, action: :admin)

    suite = create_suite

    request = Exemptions::ExemptionRequest.create!(
      resource_owner: suite,
      requester: @org_member,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type: "push_ruleset_bypass",
    )

    Exemptions::ExemptionResponse.create!(
      exemption_request: request,
      reviewer: @org_admin,
      status: :approved
    )

    refute Exemptions::ExemptionResponse.new(
      exemption_request: request,
      reviewer: @org_admin,
      status: :approved
    ).valid?

    refute Exemptions::ExemptionResponse.new(
      exemption_request: request,
      reviewer: @org_admin,
      status: :rejected
    ).valid?

    assert Exemptions::ExemptionResponse.new(
      exemption_request: request,
      reviewer: org_admin_2,
      status: :approved
    ).valid?
  end

  test "send notification on create and update" do
    suite = create_suite

    request = Exemptions::ExemptionRequest.create!(
      resource_owner: suite,
      requester: @org_member,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type: "push_ruleset_bypass",
    )

    response = Exemptions::ExemptionResponse.build(
      exemption_request: request,
      reviewer: @org_admin,
      status: :approved
    )

    ExemptionRequestMailer.expects(:request_status_changed).with(
      request,
      response,
      "Your request to bypass push rules has an update",
      "You are receiving this email because you submitted this request.",
      "#{T.must(request.repository).permalink}/exemptions/1"
    ).returns(stub(deliver_later: nil))

    response.save!

    response.status = :dismissed

    ExemptionRequestMailer.expects(:request_status_changed).with(
      request,
      response,
      "Your request to bypass push rules has an update",
      "You are receiving this email because you submitted this request.",
      "#{T.must(request.repository).permalink}/exemptions/1"
    ).returns(stub(deliver_later: nil))

    response.save!
  end

  context "hydro event" do
    test "publishes on approval" do
      suite = create_suite

      request = Exemptions::ExemptionRequest.create!(
        resource_owner: suite,
        requester: @org_member,
        resource_identifier: suite.after_oid,
        repository: suite.repository,
        request_type: "push_ruleset_bypass",
      )

      response = Exemptions::ExemptionResponse.create!(
        exemption_request: request,
        reviewer: @org_admin,
        status: :approved
      )

      request.reload

      if GitHub.flipper[:delegated_bypass_hydro_events].enabled?
        assert_hydro_messages(count: 1, schema: "github.exemptions.v0.ExemptionResponseSubmitted")
        assert_hydro_published({
          request_context: nil, # no request context in this case
          actor: Hydro::EntitySerializer.user(@org_admin),
          exemption_request: Hydro::EntitySerializer.exemption_request(request),
          exemption_response: Hydro::EntitySerializer.exemption_response(response),
        }, schema: "github.exemptions.v0.ExemptionResponseSubmitted")
      else
        assert_hydro_messages(count: 0, schema: "github.exemptions.v0.ExemptionResponseSubmitted")
      end
    end

    test "publishes on rejection" do
      suite = create_suite

      request = Exemptions::ExemptionRequest.create!(
        resource_owner: suite,
        requester: @org_member,
        resource_identifier: suite.after_oid,
        repository: suite.repository,
        request_type: "push_ruleset_bypass",
      )

      response = Exemptions::ExemptionResponse.create!(
        exemption_request: request,
        reviewer: @org_admin,
        status: :rejected
      )

      request.reload

      if GitHub.flipper[:delegated_bypass_hydro_events].enabled?
        assert_hydro_messages(count: 1, schema: "github.exemptions.v0.ExemptionResponseSubmitted")
        assert_hydro_published({
          request_context: nil, # no request context in this case
          actor: Hydro::EntitySerializer.user(@org_admin),
          exemption_request: Hydro::EntitySerializer.exemption_request(request),
          exemption_response: Hydro::EntitySerializer.exemption_response(response),
        }, schema: "github.exemptions.v0.ExemptionResponseSubmitted")
      else
        assert_hydro_messages(count: 0, schema: "github.exemptions.v0.ExemptionResponseSubmitted")
      end
    end

    test "publishes on dismiss" do
      suite = create_suite

      request = Exemptions::ExemptionRequest.create!(
        resource_owner: suite,
        requester: @org_member,
        resource_identifier: suite.after_oid,
        repository: suite.repository,
        request_type: "push_ruleset_bypass",
      )

      response = Exemptions::ExemptionResponse.create!(
        exemption_request: request,
        reviewer: @org_admin,
        status: :rejected
      )

      response.update!(status: :dismissed)

      request.reload

      if GitHub.flipper[:delegated_bypass_hydro_events].enabled?
        assert_hydro_messages(count: 1, schema: "github.exemptions.v0.ExemptionResponseDismissed")
        assert_hydro_published({
          request_context: nil, # no request context in this case
          actor: Hydro::EntitySerializer.user(@org_admin),
          exemption_request: Hydro::EntitySerializer.exemption_request(request),
          exemption_response: Hydro::EntitySerializer.exemption_response(response),
        }, schema: "github.exemptions.v0.ExemptionResponseDismissed")
      else
        assert_hydro_messages(count: 0, schema: "github.exemptions.v0.ExemptionResponseDismissed")
      end
    end
  end

  private

  def create_suite(ruleset: nil)
    push_ruleset = ruleset || create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    config = create(:repository_rule_configuration, repository_ruleset: push_ruleset, rule_type: "max_file_path_length", parameters: {
      max_file_path_length: 10
    })
    ref_update = create_branch_update(@org_repo, name: "main")
    run = RuleEngine::RuleRun.failure(rule_config: config, ref_update: ref_update, message: "failed")
    suite = RuleEngine::RuleSuite.for_ref_update(ref_update: ref_update, rule_runs: [run], actor: @org_member)
    suite.save!

    suite
  end
end
