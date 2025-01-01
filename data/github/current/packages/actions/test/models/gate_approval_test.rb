# typed: true
# frozen_string_literal: true

require "test_helper"

class GateApprovalTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @owner = create(:user)
    @org = create(:enterprise_linked_organization, admin: @owner)
    @org.add_member(@owner)
    @repo = create(:private_repository, owner: @org)
    @env = create(:environment, repository: @repo)
    @team = @org.teams.create(name: "Approvers", privacy: :closed)
    @team.add_member @owner
    @team.add_repository @repo, :admin
  end

  setup do
    make_trusted_oauth_apps_owner
    actions_app = create :launch_integration
    GitHub.stubs(:launch_github_app).returns(actions_app)
    actions_installation = make_integration_installation(integration: actions_app, repository: @repo)

    GitHub.stubs(:actions_enabled?).returns(true)
  end

  def create_gate_request(approver: @owner, environment: @env)
    make_trusted_oauth_apps_owner
    gate = create(:gate, :approval, approver: approver, environment: environment)
    create(:gate_request, gate: gate)
  end

  def create_custom_gate_request(approver: @owner, environment: @env)
    make_trusted_oauth_apps_owner

    github_app = create :integration, default_permissions: { "checks" => :write }, name: "Super-Duper", owner: @owner, url: "http://super-duper.com"

    gate = create(:gate, :custom, environment: environment, integration: github_app)
    create(:gate_request, gate: gate)
  end

  context "#user_can_approve" do
    test "produces an exception if the user cannot approve" do
      gate = create(:gate, environment: @env)
      gate_request = create(:gate_request, gate: gate)

      assert_raises(ActiveRecord::RecordInvalid) do
        create(:gate_approval, gate_request: gate_request, user: @owner, state: "approved")
      end
    end

    test "works if the user is an approver" do
      create(:gate_approval, gate_request: create_gate_request, user: @owner, state: "approved")
    end

    test "sets team and not user id on team approval" do
      events = assert_performed_audit_entries(count: 1, only: "workflows.approve_workflow_job") do
        create(:gate_approval, gate_request: create_gate_request, user: @owner, approver: @team, state: "approved")
      end

      assert_equal last_performed_audit_entries, events

      gate_approval = GateApproval.last

      expected_payload = {
        action: "workflows.approve_workflow_job",
        gate_approval_id: gate_approval.id,
        actor_id: @owner.id,
        team_id: @team.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        org_id: @org.id,
        org: @org.login,
        workflow_run_id: gate_approval.workflow_run.id,
        run_number: gate_approval.workflow_run.run_number,
        env_id: @env.id,
        env_name: @env.name,
        business_id: @org.business.id
      }

      event = events.first

      assert_subset_hash expected_payload, event
    end

    test "creates an audit log entry on approval" do
      events = assert_performed_audit_entries(count: 1, only: "workflows.approve_workflow_job") do
        create(:gate_approval, gate_request: create_gate_request, user: @owner, approver: @owner, state: "approved")
      end

      assert_equal last_performed_audit_entries, events

      gate_approval = GateApproval.last

      expected_payload = {
        action: "workflows.approve_workflow_job",
        gate_approval_id: gate_approval.id,
        actor_id: @owner.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        org_id: @org.id,
        org: @org.login,
        workflow_run_id: gate_approval.workflow_run.id,
        run_number: gate_approval.workflow_run.run_number,
        env_id: @env.id,
        env_name: @env.name,
        business_id: @org.business.id
      }

      event = events.first

      assert_subset_hash expected_payload, event
    end

    test "creates an audit log entry on rejection" do
      events = assert_performed_audit_entries(count: 1, only: "workflows.reject_workflow_job") do
        create(:gate_approval, gate_request: create_gate_request, user: @owner, approver: @owner, state: "rejected")
      end

      assert_equal last_performed_audit_entries, events

      gate_approval = GateApproval.last

      expected_payload = {
        action: "workflows.reject_workflow_job",
        gate_approval_id: gate_approval.id,
        actor_id: @owner.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        workflow_run_id: gate_approval.workflow_run.id,
        run_number: gate_approval.workflow_run.run_number,
        env_id: @env.id,
        env_name: @env.name,
        business_id: @org.business.id
      }

      event = events.first

      assert_subset_hash expected_payload, event
    end

    test "creates an audit log entry on approval update" do
      gate_approval = create(:gate_approval, gate_request: create_gate_request, user: @owner, approver: @owner, state: "rejected")

      events = assert_performed_audit_entries(count: 1, only: "workflows.approve_workflow_job") do
        gate_approval.update!(state: "approved")
      end

      assert_equal last_performed_audit_entries, events

      gate_approval = GateApproval.last

      expected_payload = {
        action: "workflows.approve_workflow_job",
        gate_approval_id: gate_approval.id,
        actor_id: @owner.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        org_id: @org.id,
        org: @org.login,
        workflow_run_id: gate_approval.workflow_run.id,
        run_number: gate_approval.workflow_run.run_number,
        env_id: @env.id,
        env_name: @env.name,
        business_id: @org.business.id
      }

      event = events.first

      assert_subset_hash expected_payload, event
    end

    test "works for any user if rejecting for a deleted environment" do
      deleted_env = create :environment, repository: @repo
      deleted_env.destroy

      create(:gate_approval, gate_request: create_gate_request(environment: deleted_env), user: @owner, state: "rejected")
    end

    test "prevents any user from rejecting for an existing environment" do
      env = create :environment, repository: @repo
      gate = create(:gate, environment: env)
      gate_request = create(:gate_request, gate: gate)

      assert_raises(ActiveRecord::RecordInvalid) do
        create(:gate_approval, gate_request: gate_request, user: @owner, state: "rejected")
      end
    end

    test "does create an audit log entry for skipped gate requests" do
      events = assert_performed_audit_entries(count: 1, only: "workflows.bypass_protection_rules") do
        create(:gate_approval, gate_request: create_gate_request, user: @owner, approver: @owner, state: "skipped")
      end

      assert_equal last_performed_audit_entries, events

      gate_approval = GateApproval.last

      expected_payload = {
        action: "workflows.bypass_protection_rules",
        gate_approval_id: gate_approval.id,
        actor_id: @owner.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        workflow_run_id: gate_approval.workflow_run.id,
        run_number: gate_approval.workflow_run.run_number,
        env_id: @env.id,
        env_name: @env.name,
        business_id: @org.business.id
      }

      event = events.first

      assert_subset_hash expected_payload, event
    end

    test "does create an audit log entry for comment from custom gate on pending gate request" do
      custom_gate_request = create_custom_gate_request
      app = custom_gate_request.gate.integration.bot

      events = assert_performed_audit_entries(count: 1, only: "workflows.comment_workflow_job") do
        GateApprovalLog.post_comment_for_pending_custom_gate_requests(app, [custom_gate_request], "this is a comment")
      end

      assert_equal last_performed_audit_entries, events

      gate_approval = GateApproval.last
      gate_approval_log = GateApprovalLog.last
      gate_approval_log_comment = gate_approval_log.comment

      expected_payload = {
        action: "workflows.comment_workflow_job",
        gate_approval_id: gate_approval.id,
        actor_id: app.id,
        repo: @repo.nwo,
        repo_id: @repo.id,
        workflow_run_id: gate_approval.workflow_run.id,
        run_number: gate_approval.workflow_run.run_number,
        env_id: @env.id,
        env_name: @env.name,
        business_id: @org.business.id,
        comment: gate_approval_log_comment
      }

      event = events.first

      assert_subset_hash expected_payload, event
    end
  end
end
