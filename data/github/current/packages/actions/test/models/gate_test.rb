# typed: false
# frozen_string_literal: true

require "test_helper"

class GateTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @owner = create(:user)
    @org = create(:organization)
    @org.add_member(@owner)
    @repo = create(:repository, owner: @org)
    @env = create(:environment, repository: @repo)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
  end

  context "#destroy" do
    test "it creates a cancelled gate approval log" do
      env = create(:environment, :with_approval_gate, :with_wait_time_gate, repository: @repo)
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)
      gate = env.approval_gate
      gate_request = GateRequest.create_or_update_gate_request(gate, check_run, "token", nil)
      GitHub.context.push(actor_id: @owner.id)

      gate.destroy

      assert gate_request.reload.rejected?
      approval_log = GateApprovalLog.find_by(check_suite: check_suite)
      assert approval_log.canceled?
      assert_equal "Required reviewers protection rule deleted.", approval_log.comment
    end

    test "it queues NotifyRejectedGatesJob for any rejected gate requests" do
      env = create(:environment, :with_approval_gate, repository: @repo)
      gate = env.approval_gate
      gate_request = create(:gate_request, gate: gate, state: :closed)
      GitHub.context.push(actor_id: @owner.id)

      NotifyRejectedGatesJob.expects(:perform_later).with(gate_request_ids: [gate_request.id], repository_global_relay_id: @repo.global_relay_id, gate_global_relay_id: gate.global_relay_id)

      gate.destroy
    end

    test "do not raise errors if the environment is missing" do
      env = create(:environment, :with_approval_gate, repository: @repo)
      gate = env.approval_gate

      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        env.destroy
      end

      gate.destroy
    end

    test "do not raise errors if the environment's repository is missing" do
      env = create(:environment, :with_approval_gate, repository: @repo)
      gate = env.approval_gate

      perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
        @repo.destroy
      end

      gate.destroy
    end

    test "create instruments an event" do
      GitHub.context.push(actor_id: @owner.id)

      env = nil
      events = assert_performed_audit_entries(count: 1, only: "environment.add_protection_rule") do
        env = create(:environment, :with_approval_gate, repository: @repo)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.add_protection_rule",
        actor: @owner.owner.login,
        environment_name: env.name,
        environment_id: env.id,
        gate_type: "manual_approval",
        approvers: []
      }

      assert_subset_hash expected_payload, events.first
    end

    test "destroy instruments an event" do
      GitHub.context.push(actor_id: @owner.id)

      env = create(:environment, :with_wait_time_gate, repository: @repo)
      events = assert_performed_audit_entries(count: 1, only: "environment.remove_protection_rule") do
        env.wait_gate.destroy
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.remove_protection_rule",
        actor: @owner.login,
        environment_name: env.name,
        environment_id: env.id,
        gate_type: "timeout"
      }

      assert_subset_hash expected_payload, events.first
    end
  end
end
