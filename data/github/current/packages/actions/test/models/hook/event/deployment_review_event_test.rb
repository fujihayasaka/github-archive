# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/launch_test_helpers"

class HookEventDeploymentReviewEventTest < GitHub::TestCase
  include HookEventTestHelper, LaunchTestHelpers

  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @owner = create :user
    @org = create :organization
    @org.add_member(@owner)
    @repo = create :repository, owner: @org
    @repo2 = create :repository, owner: @org
    @env = create :environment, repository: @repo
    @env2 = create :environment, repository: @repo
    @env_repo2 = create :environment, repository: @repo2
    @team = @org.teams.create(name: "Approvers", privacy: :closed)
    @team.add_member @owner
    @team.add_repository @repo, :admin

    @check_suite = create :check_suite_for_actions_app, :with_name, repository: @repo
    @check_run_for_owner = create :check_run, check_suite: @check_suite
    @check_run_for_owner2 = create :check_run, check_suite: @check_suite
    @check_run_for_team = create :check_run, check_suite: @check_suite
    [@check_run_for_owner, @check_run_for_owner2, @check_run_for_team].each do |check_run|
      check_run.create_deployment(@env.name)
      check_run.update_status_and_deployment_from_gates
    end

    @deployment_status_for_owner = @check_run_for_owner.deployment.statuses[0]
    @deployment_status_for_team = @check_run_for_team.deployment.statuses[0]

    @gate_approver_owner = @env.add_approver(@owner)
    @gate_approver_owner2 = @env2.add_approver(@owner)
    @gate_approver_team = @env.add_approver(@team)
    @gate_request_owner = create(:gate_request, gate: @gate_approver_owner.gate, check_run: @check_run_for_owner)
    @gate_request_owner2 = create(:gate_request, gate: @gate_approver_owner2.gate, check_run: @check_run_for_owner2)
    @gate_request_team = create(:gate_request, gate: @gate_approver_team.gate, check_run: @check_run_for_team)
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::DeploymentReviewEvent, :action
  end

  test "returns the specified deployment record" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "review"
    assert_equal @deployment_status_for_owner.deployment, event.deployment
  end

  test "returns the repo for specified status" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "review"
    assert_equal @deployment_status_for_owner.repository, event.target_repository
  end

  test "returns the user who created the specified status" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "review"
    assert_equal @deployment_status_for_owner.creator, event.actor
  end

  test "returns the action for the specified deployment status" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "review"
    assert_equal "review", event.action
  end

  test "returns the check_suite correctly" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "review"
    assert_equal @check_suite, event.check_suite
  end

  test "returns the workflow_run correctly" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "review"
    assert_equal @check_suite.workflow_run, event.workflow_run
  end

  test "returns the gate_requests correctly" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "review"
    assert_equal 1, event.gate_requests.count

    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_team.id, action: "review"
    assert_equal 1, event.gate_requests.count
  end

  test "returns the environment correctly" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "review"
    assert_equal @env.name, event.environment

    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_team.id, action: "review"
    assert_equal @env.name, event.environment
  end

  test "returns the reviewers correctly" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "review"
    assert_equal 2, event.reviewers.count

    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_team.id, action: "review"
    assert_equal 2, event.reviewers.count
  end

  test "returns the reviewers correctly after gate is deleted" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "review"
    @gate_approver_owner.gate.delete
    assert_equal 0, event.reviewers.count
  end

  test "returns the user who approved the requests when approving multiple requests" do
    mock_notify_gate(@gate_request_owner, true)
    mock_notify_gate(@gate_request_owner2, true)
    mock_notify_gate(@gate_request_team, true)
    gate_approval_log = GateApprovalLog.approve_or_reject_requests(@owner, [@gate_request_owner, @gate_request_owner2, @gate_request_team], "approved", "LGTM")
    event = Hook::Event::DeploymentReviewEvent.new action: "approved", gate_approval_log_id: gate_approval_log.id, comment: "go forth"
    assert_equal @owner, event.approver
    assert_equal "open", event.gate_requests[0].state
    assert_equal "open", event.gate_requests[1].state
    assert_equal "open", event.gate_requests[2].state
    assert_equal 3, event.gate_requests.count
    assert_equal true, event.deliverable?
  end

  test "returns the user who rejected the requests when rejecting multiple requests" do
    mock_notify_gate(@gate_request_owner, false)
    mock_notify_gate(@gate_request_owner2, false)
    mock_notify_gate(@gate_request_team, false)
    gate_approval_log = GateApprovalLog.approve_or_reject_requests(@owner, [@gate_request_owner, @gate_request_owner2, @gate_request_team], "rejected", "stop!")
    event = Hook::Event::DeploymentReviewEvent.new action: :rejected, gate_approval_log_id: gate_approval_log.id, comment: "stop!"
    assert_equal @owner, event.approver
    assert_equal "rejected", event.gate_requests[0].state
    assert_equal "rejected", event.gate_requests[1].state
    assert_equal "rejected", event.gate_requests[2].state
    assert_equal 3, event.gate_requests.count
    assert_equal true, event.deliverable?
  end

  context "#deliverable?" do
    test "returns false if the DeploymentStatus is not found" do
      event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: 0, action: "review"
      refute_predicate event, :deliverable?
    end

    test "returns false if the repository doesn't exist" do
      # TODO: Because of the way the `CheckSuite#code_scanning_app?` method
      # has been implemented, this test requires the code scanning app to
      # exist, even though it has nothing to do with it. We should change that
      # to instead rely on `Apps::Privileged.capable?`
      create(:code_scanning_integration)

      check_suite = create :check_suite, repository: @repo2
      check_run = create :check_run, check_suite: check_suite
      check_run.create_deployment(@env_repo2.name)
      check_run.update_status_and_deployment_from_gates
      deployment_status = check_run.deployment.statuses[0]
      event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: deployment_status.id, action: "review"
      deployment_status.repository.destroy
      deployment_status.reload
      refute_predicate event, :deliverable?
    end

    test "returns false if there are no approvers" do
      check_run = create :check_run, check_suite: @check_suite
      env = create :environment, repository: @repo, name: "test"
      deployment = check_run.create_deployment(env)
      check_run.update_status_and_deployment_from_gates
      event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: deployment.statuses[0].id, action: "review"
      refute_predicate event, :deliverable?
    end
  end
end
