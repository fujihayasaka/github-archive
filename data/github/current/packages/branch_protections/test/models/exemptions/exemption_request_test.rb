# typed: true
# frozen_string_literal: true

require "test_helper"

class ExemptionRequestTest < GitHub::TestCase
  include RulesEngine::RefUpdateTestHelper
  include HydroTestHelpers

  fixtures do
    @biz = Business.first || create(:business)
    @org_admin = create(:user)
    @org = create(:business_plus_organization, name: "org1", admin: @org_admin, business: @biz)

    @team = create(:team, organization: @org, privacy: :closed)
    @team.add_member(@org_admin)

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

  test "owner and business are populated" do
    suite = create_suite

    request = Exemptions::ExemptionRequest.create!(
      resource_owner: suite,
      requester: @org_member,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type: "push_ruleset_bypass",
    )

    assert request.valid?
    assert_equal suite.repository.owner, request.owner
    assert_equal suite.repository.owner.business, request.business
  end

  test "computes pending status for unapproved push ruleset exemption" do
    suite = create_suite

    request = Exemptions::ExemptionRequest.create!(
      resource_owner: suite,
      requester: @org_member,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type: "push_ruleset_bypass",
    )

    assert request.pending?
    assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Pending, request.compute_status
  end

  test "computes approved status for approved push ruleset exemption" do
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

    request.reload

    assert request.pending?
    assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Approved, request.compute_status
  end

  test "computes pending status for dismissed push ruleset exemption" do
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
      status: :dismissed
    )

    request.reload

    assert request.pending?
    assert_equal Exemptions::ExemptionEvaluator::EvaluationResult::Pending, request.compute_status
  end

  test "send notifications in background" do
    push_ruleset = create(:repository_ruleset, :org_admin_bypass_any, target: "push", source: @org_repo)
    push_ruleset.bypass_actors.create!(
      actor: @team,
    )

    suite = create_suite(ruleset: push_ruleset)

    request = Exemptions::ExemptionRequest.build(
      resource_owner: suite,
      requester: @org_member,
      resource_identifier: suite.after_oid,
      repository: suite.repository,
      request_type: "push_ruleset_bypass",
    )

    ExemptionRequestMailer.expects(:push_bypass).never

    request.save!

    assert_enqueued_with(job: ExemptionRequestEmailJob, args: [request])
  end

  context "hydro event" do
    test "publishes on creation" do
      suite = create_suite

      request = Exemptions::ExemptionRequest.create!(
        resource_owner: suite,
        requester: @org_member,
        resource_identifier: suite.after_oid,
        repository: suite.repository,
        request_type: "push_ruleset_bypass",
      )
      if GitHub.flipper[:delegated_bypass_hydro_events].enabled?
        assert_hydro_messages(count: 1, schema: "github.exemptions.v0.ExemptionRequestCreated")
        assert_hydro_published({
          request_context: nil, # no request context in this case
          actor: Hydro::EntitySerializer.user(@org_member),
          exemption_request: Hydro::EntitySerializer.exemption_request(request),
        }, schema: "github.exemptions.v0.ExemptionRequestCreated")
      else
        assert_hydro_messages(count: 0, schema: "github.exemptions.v0.ExemptionRequestCreated")
      end
    end

    test "publishes on cancellation" do
      suite = create_suite

      request = Exemptions::ExemptionRequest.create!(
        resource_owner: suite,
        requester: @org_member,
        resource_identifier: suite.after_oid,
        repository: suite.repository,
        request_type: "push_ruleset_bypass",
      )

      request.update!(status: Exemptions::ExemptionRequest::STATUSES[:cancelled])

      if GitHub.flipper[:delegated_bypass_hydro_events].enabled?
        assert_hydro_messages(count: 1, schema: "github.exemptions.v0.ExemptionRequestCancelled")
        assert_hydro_published({
          request_context: nil, # no request context in this case
          actor: Hydro::EntitySerializer.user(@org_member),
          exemption_request: Hydro::EntitySerializer.exemption_request(request),
        }, schema: "github.exemptions.v0.ExemptionRequestCancelled")
      else
        assert_hydro_messages(count: 0, schema: "github.exemptions.v0.ExemptionRequestCancelled")
      end
    end

    test "publishes on completion" do
      suite = create_suite

      request = Exemptions::ExemptionRequest.create!(
        resource_owner: suite,
        requester: @org_member,
        resource_identifier: suite.after_oid,
        repository: suite.repository,
        request_type: "push_ruleset_bypass",
      )

      request.update!(status: Exemptions::ExemptionRequest::STATUSES[:completed])

      if GitHub.flipper[:delegated_bypass_hydro_events].enabled?
        assert_hydro_messages(count: 1, schema: "github.exemptions.v0.ExemptionRequestCompleted")
        assert_hydro_published({
          request_context: nil, # no request context in this case
          actor: Hydro::EntitySerializer.user(@org_member),
          exemption_request: Hydro::EntitySerializer.exemption_request(request),
        }, schema: "github.exemptions.v0.ExemptionRequestCompleted")
      else
        assert_hydro_messages(count: 0, schema: "github.exemptions.v0.ExemptionRequestCompleted")
      end
    end
  end

  context "has_undismissed_review_by_any_reviewer?" do
    test "returns false if there are no responses at all" do
      suite = create_suite
      request = Exemptions::ExemptionRequest.create!(
        resource_owner: suite,
        requester: @org_member,
        resource_identifier: suite.after_oid,
        repository: suite.repository,
        request_type: "secret_scanning",
      )
      assert request.responses.empty?

      refute request.has_undismissed_review_by_any_reviewer?
    end

    test "returns true if there is an approved or rejected response" do
      reviewer = create(:user)
      second_reviewer = create(:user)
      suite = create_suite
      request = Exemptions::ExemptionRequest.create!(
        resource_owner: suite,
        requester: @org_member,
        resource_identifier: suite.after_oid,
        repository: suite.repository,
        request_type: "secret_scanning",
      )
      SecretScanning::Services::DelegatedBypassService.stubs(:can_review_bypass_request?).returns(true)
      approval = Exemptions::ExemptionResponse.approve!(request, reviewer)
      assert request.reload.has_undismissed_review_by_any_reviewer?
      rejection = Exemptions::ExemptionResponse.reject!(request, second_reviewer)
      assert request.reload.has_undismissed_review_by_any_reviewer?

      # Dismiss both reviews
      Exemptions::ExemptionResponse.where(id: approval.id).first!.update(status: :dismissed)
      Exemptions::ExemptionResponse.where(id: rejection.id).first!.update(status: :dismissed)

      refute request.reload.has_undismissed_review_by_any_reviewer?
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
