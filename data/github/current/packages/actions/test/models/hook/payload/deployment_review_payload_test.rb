# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/launch_test_helpers"

class HookPayloadDeploymentReviewPayloadTest < GitHub::TestCase
  include LaunchTestHelpers
  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @owner = create :user
    @org = create :organization
    @org.add_member(@owner)
    @repo = create :repository, owner: @org
    @env = create :environment, repository: @repo
    @env2 = create :environment, repository: @repo
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
    @gate_request_team = create(:gate_request, gate: @gate_approver_team.gate, check_run: @check_run_for_team)
    @gate_request_owner2 = create(:gate_request, gate: @gate_approver_owner2.gate, check_run: @check_run_for_owner2)
  end

  test "payload review requested" do
    event = Hook::Event::DeploymentReviewEvent.new deployment_status_id: @deployment_status_for_owner.id, action: "requested"
    payload = Hook::Payload::DeploymentReviewPayload.new event
    payload_hash = payload.to_hash
    user_reviewer = payload_hash[:reviewers].find { |reviewer| reviewer[:type] == "User" }
    team_reviewer = payload_hash[:reviewers].find { |reviewer| reviewer[:type] == "Team" }

    assert_equal @env.name, payload_hash[:environment]
    assert_equal "requested", payload_hash[:action]
    assert_equal Api::Serializer.serialize(:workflow_run_hash, @check_suite.workflow_run), payload_hash[:workflow_run]
    assert_equal @check_suite.name, payload_hash[:workflow_run][:name]
    assert_equal 2, payload_hash[:reviewers].count
    assert_equal "User", user_reviewer[:type]
    assert_equal @owner.id, user_reviewer[:reviewer][:id]
    assert_equal "Team", team_reviewer[:type]
    assert_equal @team.id, team_reviewer[:reviewer][:id]
    assert payload_hash[:since]
  end

  test "payload with multiple approvals" do
    mock_notify_gate(@gate_request_owner2, true)
    mock_notify_gate(@gate_request_owner, true)
    mock_notify_gate(@gate_request_team, true)
    comment = "go forth"
    gate_approval_log = GateApprovalLog.approve_or_reject_requests(@owner, [@gate_request_owner, @gate_request_owner2, @gate_request_team], "approved", comment)
    event = Hook::Event::DeploymentReviewEvent.new action: :approved, gate_approval_log_id: gate_approval_log.id, comment: comment
    payload = Hook::Payload::DeploymentReviewPayload.new event
    payload_hash = payload.to_hash

    assert_equal :approved, payload_hash[:action]
    assert_equal Api::Serializer.serialize(:workflow_run_hash, @check_suite.workflow_run), payload_hash[:workflow_run]
    assert_equal @check_suite.name, payload_hash[:workflow_run][:name]
    assert payload_hash[:since]
    assert_equal comment, payload_hash[:comment]
    assert_equal @owner.id, payload_hash[:approver][:id]
    assert_equal 3, payload_hash[:workflow_job_runs].count
    assert_equal @env.name, payload_hash[:workflow_job_runs][0][:environment]
  end

  test "payload with multiple rejections" do
    mock_notify_gate(@gate_request_owner2, false)
    mock_notify_gate(@gate_request_owner, false)
    mock_notify_gate(@gate_request_team, false)
    comment = "stop!"
    gate_approval_log = GateApprovalLog.approve_or_reject_requests(@owner, [@gate_request_owner, @gate_request_owner2, @gate_request_team], "rejected", comment)
    event = Hook::Event::DeploymentReviewEvent.new action: :rejected, gate_approval_log_id: gate_approval_log.id, comment: comment
    payload = Hook::Payload::DeploymentReviewPayload.new event
    payload_hash = payload.to_hash

    assert_equal :rejected, payload_hash[:action]
    assert_equal Api::Serializer.serialize(:workflow_run_hash, @check_suite.workflow_run), payload_hash[:workflow_run]
    assert_equal @check_suite.name, payload_hash[:workflow_run][:name]
    assert payload_hash[:since]
    assert_equal comment, payload_hash[:comment]
    assert_equal @owner.id, payload_hash[:approver][:id]
    assert_equal 3, payload_hash[:workflow_job_runs].count
    assert_equal @env.name, payload_hash[:workflow_job_runs][0][:environment]
  end

end
