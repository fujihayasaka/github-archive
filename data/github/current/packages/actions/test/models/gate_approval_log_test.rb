# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/launch_test_helpers"

class GateApprovalLogTest < GitHub::TestCase
  include LaunchTestHelpers

  fixtures do
    @owner = create(:user)
    @org = create(:organization)
    @org.add_member(@owner)
    @repo = create(:private_repository, owner: @org)
    @env = create(:environment, repository: @repo)
    @team = @org.teams.create(name: "Approvers", privacy: :closed)
    @team.add_member @owner
    @team.add_repository @repo, :admin
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
  end

  context "#approve_or_reject_requests" do
    test "produces an exception if the user cannot approve" do
      gate = create(:gate, environment: @env)
      gate_request = create(:gate_request, gate: gate)

      assert_raises_with_message(ArgumentError, "User is not a valid approver") do
        GateApprovalLog.approve_or_reject_requests(@owner, [gate_request], "approved", "LGTM")
      end

      assert_equal [], gate_request.reload.gate_approvals
      refute GateApprovalLog.find_by(check_suite: gate_request.check_run.check_suite)
    end

    test "approves a gate request and generates a log" do
      gate_approver = @env.add_approver(@owner)
      gate = gate_approver.gate

      env2 = create(:environment, repository: @repo)
      gate_approver2 = env2.add_approver(@owner)
      gate2 = gate_approver2.gate
      check_suite = create(:check_suite_for_actions_app)
      refute_nil check_suite.workflow_run
      check_run = create(:check_run, check_suite: check_suite)
      check_run2 = create(:check_run, check_suite: check_suite)

      gate_request = create(:gate_request, gate: gate, check_run: check_run)
      gate_request2 = create(:gate_request, gate: gate2, check_run: check_run2)
      refute_nil gate_request.check_run.check_suite.workflow_run

      mock_notify_gate(gate_request, true)
      mock_notify_gate(gate_request2, true)

      gate_approval_log = GateApprovalLog.approve_or_reject_requests(@owner, [gate_request, gate_request2], "approved", "LGTM")

      assert_equal "open", gate_request.reload.state

      assert_equal "LGTM", gate_approval_log.comment
      assert_equal @owner, gate_approval_log.user
      assert_equal gate_request.check_run.check_suite, gate_approval_log.check_suite

      assert_equal 2, gate_approval_log.gate_approvals.size
      gate_approval = gate_approval_log.gate_approvals.first
      assert_equal @owner, gate_approval.user
      assert_equal gate_request, gate_approval.gate_request
      assert_equal @repo, gate_approval.repository
      assert_equal "approved", gate_approval.state
    end

    test "rejects a gate request and its siblings and generates logs" do
      gate_approver = @env.add_approver(@owner)
      manual_gate = gate_approver.gate
      timer_gate = create(:gate, :wait_time, environment: @env)
      custom_gate = create(:gate, :custom, environment: @env)

      check_suite = create(:check_suite_for_actions_app)
      check_run = create(:check_run, check_suite: check_suite)

      manual_gate_request = create(:gate_request, gate: manual_gate, check_run: check_run)
      timer_gate_request = create(:gate_request, gate: timer_gate, check_run: check_run)
      custom_gate_request = create(:gate_request, gate: custom_gate, check_run: check_run)

      mock_notify_gate(manual_gate_request, false)

      gate_approval_log = GateApprovalLog.approve_or_reject_requests(@owner, [manual_gate_request], "rejected", "LBTM")
      gate_approval = gate_approval_log.gate_approvals.first

      [manual_gate_request, timer_gate_request, custom_gate_request].each do |gate_request|
        assert_equal "rejected", gate_request.reload.state
      end

      [timer_gate_request, custom_gate_request].each do |gate_request|
        gate_approvals = gate_request.gate_approvals
        assert_equal 1, gate_approvals.size
        assert gate_approvals.first
        assert_equal "canceled", gate_approvals.first.state
        assert_equal "canceled", gate_approvals.first.gate_approval_log.state

        assert_equal @owner, gate_approvals.first.user
        assert_equal @owner, gate_approvals.first.gate_approval_log.user

        assert_equal GateApprovalLog::SIBLING_CANCELLATION_MESSAGE, gate_approvals.first.gate_approval_log.comment
      end

      assert_equal 1, gate_approval_log.gate_approvals.size
      assert_equal "rejected", gate_approval_log.state
      assert_equal "rejected", gate_approval.state
      assert_equal @owner, gate_approval_log.user
      assert_equal @owner, gate_approval.user
      assert_equal "LBTM", gate_approval_log.comment
    end

    test "uses the launch lab client for a lab workflow" do
      launch_lab_app = GitHub.launch_lab_github_app || create(:launch_lab_integration)
      GitHub.stubs(:launch_lab_github_app).returns(launch_lab_app)
      launch_lab_check_suite = create(:check_suite_for_actions_app, github_app: launch_lab_app, repository: @repo)
      check_run = create(:check_run, check_suite: launch_lab_check_suite)

      gate_approver = @env.add_approver(@owner)
      gate = gate_approver.gate
      gate_request = create(:gate_request, gate: gate, check_run: check_run)

      mock_notify_gate(gate_request, true, is_lab: true)
      GateApprovalLog.approve_or_reject_requests(@owner, [gate_request], "approved", "LGTM")
    end

    test "returns the ghost user if the user was destroyed" do
      gate_approver = @env.add_approver(@owner)
      gate = gate_approver.gate
      gate_request = create(:gate_request, gate: gate)

      mock_notify_gate(gate_request, true)

      gate_approval_log = GateApprovalLog.approve_or_reject_requests(@owner, [gate_request], "approved", "LGTM")

      @owner.destroy

      assert_equal User.ghost, gate_approval_log.reload.user
    end

    test "prevents a gate request to be approved twice" do
      user = create(:user)
      gate_approver = @env.add_approver(@owner)
      @env.add_approver(user)
      gate = gate_approver.gate
      gate_request = create(:gate_request, gate: gate)

      mock_notify_gate(gate_request, true)

      gate_approval_log = GateApprovalLog.approve_or_reject_requests(@owner, [gate_request], "approved", "LGTM")

      assert_raises_with_message(ArgumentError, "At least one environment has already been approved or rejected") do
        GateApprovalLog.approve_or_reject_requests(@owner, [gate_request], "approved", "LGTM")
      end

      assert_equal 1, GateApprovalLog.where(check_suite: gate_approval_log.check_suite).size
    end

    test "does not create anything if the twirp call fails" do
      gate_approver = @env.add_approver(@owner)
      gate = gate_approver.gate
      gate_request = create(:gate_request, gate: gate)

      mock_notify_gate(gate_request, true, returns_internal_error: true)

      assert_raises_with_message(ArgumentError, "There was a problem approving one of the gates") do
        GateApprovalLog.approve_or_reject_requests(@owner, [gate_request], "approved", "LGTM")
      end

      assert_equal [], gate_request.reload.gate_approvals
      refute GateApprovalLog.find_by(check_suite: gate_request.check_run.check_suite)
    end

    test "does not allow repository to be nil" do
      gate_approval_log = GateApprovalLog.create(repository: nil)
      refute_predicate gate_approval_log, :valid?
      assert_predicate gate_approval_log.errors[:repository], :any?
    end

    test "does not accept invalid states" do
      gate = create(:gate, environment: @env)
      gate_request = create(:gate_request, gate: gate)

      assert_raises_with_message(ArgumentError, "Invalid state provided") do
        GateApprovalLog.approve_or_reject_requests(@owner, [gate_request], "skipped", "I'm trying to skip this gate incorrectly")
      end

      assert_equal [], gate_request.reload.gate_approvals
      refute GateApprovalLog.find_by(check_suite: gate_request.check_run.check_suite)
    end

    test "does not approve or reject gate request that was already skipped" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)
      gate = create(:gate, environment: @env, type: "manual_approval")
      gate_request = create(:gate_request, gate: gate, state: :closed, check_run: check_run)
      mock_notify_gate(gate_request, true)

      GateApprovalLog.skip_requests(
        gate_requests: [gate_request],
        comment: "Skipped by an admin",
        actor: @owner,
      )

      # try to approve
      assert_raises_with_message(ArgumentError, "At least one environment has already been approved or rejected") do
        GateApprovalLog.approve_or_reject_requests(@owner, [gate_request], "approved", "LGTM")
      end

      gate_request.reload
      assert_equal "open", gate_request.state
      assert_equal "skipped", gate_request.gate_approvals.first.gate_approval_log.state

      # try to reject
      assert_raises_with_message(ArgumentError, "At least one environment has already been approved or rejected") do
        GateApprovalLog.approve_or_reject_requests(@owner, [gate_request], "rejected", "looks bad to me")
      end

      gate_request.reload
      assert_equal "open", gate_request.state
      assert_equal "skipped", gate_request.gate_approvals.first.gate_approval_log.state
    end
  end

  context "#reject_pending_requests" do
    test "rejects any pending gate requests" do
      gate_approver = @env.add_approver(@owner)
      gate = gate_approver.gate
      gate_request = create(:gate_request, gate: gate, state: :closed)

      GateApprovalLog.reject_pending_requests(
        environment: @env,
        gate_requests: [gate_request],
        comment: "Environment deleted.",
        actor: @owner,
      )

      assert_equal "rejected", gate_request.reload.state
      assert GateApprovalLog.find_by(check_suite: gate_request.check_run.check_suite)
    end

    test "ignores any approved or rejected gate requests" do
      gate_approver = @env.add_approver(@owner)
      gate = gate_approver.gate
      rejected_gate_request = create(:gate_request, gate: gate, state: :rejected)
      approved_gate_request = create(:gate_request, gate: gate, state: :open)

      GateApprovalLog.reject_pending_requests(
        environment: @env,
        gate_requests: [rejected_gate_request, approved_gate_request],
        comment: "Environment deleted.",
        actor: @owner,
      )

      assert_equal "rejected", rejected_gate_request.reload.state
      assert_equal "open", approved_gate_request.reload.state
      refute GateApprovalLog.find_by(check_suite: rejected_gate_request.check_run.check_suite)
      refute GateApprovalLog.find_by(check_suite: approved_gate_request.check_run.check_suite)
    end
  end

  context "#skip_requests" do
    test "skips pending gate requests" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      manual_gate = create(:gate, environment: @env, type: "manual_approval")
      manual_gate_request = create(:gate_request, gate: manual_gate, state: :closed, check_run: check_run)
      timer_gate = create(:gate, environment: @env, type: "timeout")
      timer_gate_request = create(:gate_request, gate: timer_gate, state: :closed, check_run: check_run)
      custom_gate = create(:gate, environment: @env, type: "custom")
      custom_gate_request = create(:gate_request, gate: custom_gate, state: :closed, check_run: check_run)

      mock_notify_gate(manual_gate_request, true)
      mock_notify_gate(timer_gate_request, true)
      mock_notify_gate(custom_gate_request, true)

      GateApprovalLog.skip_requests(
        gate_requests: [manual_gate_request, timer_gate_request, custom_gate_request],
        comment: "Skipped by an admin",
        actor: @owner,
      )

      assert_equal "open", manual_gate_request.reload.state
      assert_equal "open", timer_gate_request.reload.state
      assert_equal "open", custom_gate_request.reload.state

      assert_equal 3, GateApprovalLog.count

      manual_gate_approval = manual_gate_request.gate_approvals.first
      manual_gate_approval_log = manual_gate_approval.gate_approval_log
      timer_gate_approval = timer_gate_request.gate_approvals.first
      timer_gate_approval_log = timer_gate_approval.gate_approval_log
      custom_gate_approval = custom_gate_request.gate_approvals.first
      custom_gate_approval_log = custom_gate_approval.gate_approval_log
      assert_equal "skipped", manual_gate_approval_log.state
      assert_equal "skipped", timer_gate_approval_log.state
      assert_equal "skipped", custom_gate_approval_log.state
    end

    test "filters out gate requests that are not closed" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)
      check_run2 = create(:check_run, check_suite: check_suite)
      check_run3 = create(:check_run, check_suite: check_suite)

      env2 = create(:environment, repository: @repo)
      env3 = create(:environment, repository: @repo)

      approved_manual_gate = create(:gate, environment: @env, type: "manual_approval")
      @env.add_approver(@owner)
      approved_manual_gate_request = create(:gate_request, gate: approved_manual_gate, state: :closed, check_run: check_run)
      rejected_manual_gate = create(:gate, environment: env2, type: "manual_approval")
      env2.add_approver(@owner)
      rejected_manual_gate_request = create(:gate_request, gate: rejected_manual_gate, state: :closed, check_run: check_run2)
      skipped_manual_gate = create(:gate, environment: env3, type: "manual_approval")
      skipped_manual_gate_request = create(:gate_request, gate: skipped_manual_gate, state: :closed, check_run: check_run3)

      mock_notify_gate(approved_manual_gate_request, true)
      mock_notify_gate(rejected_manual_gate_request, false)
      mock_notify_gate(skipped_manual_gate_request, true)

      approved_gate_approval_log = GateApprovalLog.approve_or_reject_requests(@owner, [approved_manual_gate_request], "approved", "LGTM")
      rejected_gate_approval_log = GateApprovalLog.approve_or_reject_requests(@owner, [rejected_manual_gate_request], "rejected", "looks bad")

      skipped_gate_approval_logs = GateApprovalLog.skip_requests(
        gate_requests: [approved_manual_gate_request, rejected_manual_gate_request, skipped_manual_gate_request],
        comment: "Skipped by an admin",
        actor: @owner,
      )

      approved_manual_gate_request.reload
      rejected_manual_gate_request.reload
      skipped_manual_gate.reload

      assert_equal 1, skipped_gate_approval_logs.count

      assert_equal "open", approved_manual_gate_request.state
      assert_equal "approved", approved_gate_approval_log.state

      assert_equal "rejected", rejected_manual_gate_request.state
      assert_equal "rejected", rejected_gate_approval_log.state

      assert_equal "open", skipped_manual_gate_request.state
      assert_equal "skipped", skipped_gate_approval_logs.first.state

    end

    test "returns an error if user is not an admin" do
      user = create(:user)
      @repo.add_member(user)

      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      manual_gate = create(:gate, environment: @env, type: "manual_approval")
      manual_gate_request = create(:gate_request, gate: manual_gate, state: :closed, check_run: check_run)

      assert_raises_with_message(ArgumentError, "User is not an admin of the repository") do
        GateApprovalLog.skip_requests(
          gate_requests: [manual_gate_request],
          comment: "Skipped by an admin",
          actor: user,
        )

        manual_gate_request.reload
        assert_equal "closed", manual_gate_request.state
      end
    end

    test "returns an error if gate requests spanning across multiple repos are provided" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)
      gate = create(:gate, environment: @env, type: "manual_approval")
      gate_request = create(:gate_request, gate: gate, state: :closed, check_run: check_run)

      repo2 = create(:repository, owner: @org)
      repo2_env = create(:environment, repository: repo2)
      repo2_check_suite = create(:check_suite_for_actions_app, repository: repo2)
      repo2_check_run = create(:check_run, check_suite: repo2_check_suite)
      repo2_gate = create(:gate, environment: repo2_env, type: "manual_approval")
      repo2_gate_request = create(:gate_request, gate: repo2_gate, state: :closed, check_run: repo2_check_run)

      assert_raises_with_message(ArgumentError, "User is not an admin of the repository") do
        GateApprovalLog.skip_requests(
          gate_requests: [gate_request, repo2_gate_request],
          comment: "Skipped by an admin",
          actor: @owner,
        )
      end
    end

    test "returns an error if there are no gate requests" do
      assert_raises_with_message(ArgumentError, "No pending gates found for this environment") do
        GateApprovalLog.skip_requests(
          gate_requests: nil,
          comment: "Skipped by an admin",
          actor: @owner,
        )
      end
    end
  end

  context "#comment_requests" do
    test "simple happy path: comment on single pending custom gate request" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      env = create(:environment, :with_custom_gate, repository: @repo)
      custom_gate = env.gates.first
      installation = custom_gate.integration.installations.first
      custom_gate_request = create(:gate_request, gate: custom_gate, state: :closed, check_run: check_run)

      GateApprovalLog.post_comment_for_pending_custom_gate_requests(installation.bot, [custom_gate_request], "this is a comment")

      assert_equal "closed", custom_gate_request.reload.state
      assert_equal 1, GateApprovalLog.count
      assert_equal 1, custom_gate_request.gate_approvals.count

      custom_gate_approval_log = custom_gate_request.gate_approvals.first.gate_approval_log
      assert_equal "this is a comment", custom_gate_approval_log.comment
      assert_equal installation.bot, custom_gate_approval_log.user
      assert_equal check_suite, custom_gate_approval_log.check_suite

      long_comment = "a" * 1024
      GateApprovalLog.post_comment_for_pending_custom_gate_requests(installation.bot, [custom_gate_request], long_comment)

      assert_equal "closed", custom_gate_request.reload.state
      assert_equal 2, GateApprovalLog.count
      assert_equal 2, custom_gate_request.gate_approvals.count

      custom_gate_approval_log = custom_gate_request.gate_approvals.map { |gate_approval| gate_approval.gate_approval_log }.sort_by { |approval_log| approval_log.created_at }&.last

      assert_equal long_comment, custom_gate_approval_log.comment
      assert_equal installation.bot, custom_gate_approval_log.user
      assert_equal check_suite, custom_gate_approval_log.check_suite
    end

    test "comments and then approve" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      env = create(:environment, :with_custom_gate, repository: @repo)
      custom_gate = env.gates.first
      installation = custom_gate.integration.installations.first
      custom_gate_request = create(:gate_request, gate: custom_gate, state: :closed, check_run: check_run)

      GateApprovalLog.post_comment_for_pending_custom_gate_requests(installation.bot, [custom_gate_request], "this is a comment")
      assert_equal 1, GateApprovalLog.count

      mock_notify_gate(custom_gate_request, true)
      gate_approval_log = GateApprovalLog.approve_or_reject_requests(installation.bot, [custom_gate_request], "approved", "LGTM")

      assert_equal "open", custom_gate_request.reload.state

      assert_equal "LGTM", gate_approval_log.comment
      assert_equal installation.bot, gate_approval_log.user
      assert_equal custom_gate_request.check_run.check_suite, gate_approval_log.check_suite

      assert_equal 1, gate_approval_log.gate_approvals.size
      gate_approval = gate_approval_log.gate_approvals.first
      assert_equal installation.bot, gate_approval.user
      assert_equal custom_gate_request, gate_approval.gate_request
      assert_equal @repo, gate_approval.repository
      assert_equal "approved", gate_approval.state
    end

    test "comments and break glass" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      env = create(:environment, :with_custom_gate, repository: @repo)
      custom_gate = env.gates.first
      installation = custom_gate.integration.installations.first
      custom_gate_request = create(:gate_request, gate: custom_gate, state: :closed, check_run: check_run)

      GateApprovalLog.post_comment_for_pending_custom_gate_requests(installation.bot, [custom_gate_request], "this is a comment")
      assert_equal 1, GateApprovalLog.count

      mock_notify_gate(custom_gate_request, true)
      GateApprovalLog.skip_requests(gate_requests: [custom_gate_request], comment: "Skipped by an admin", actor: @owner)

      assert_equal "open", custom_gate_request.reload.state
      assert_equal 2, GateApprovalLog.count
      assert_equal 2, custom_gate_request.gate_approvals.count

      custom_gate_approval_log = custom_gate_request.gate_approvals.find { |gate_approval| gate_approval.gate_approval_log.state == "skipped" }&.gate_approval_log
      assert_equal "Skipped by an admin", custom_gate_approval_log.comment
      assert_equal @owner, custom_gate_approval_log.user
    end

    test "comments exceed limit" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      env = create(:environment, :with_custom_gate, repository: @repo)
      custom_gate = env.gates.first
      installation = custom_gate.integration.installations.first
      custom_gate_request = create(:gate_request, gate: custom_gate, state: :closed, check_run: check_run)

      GateApprovalLog::MAX_COMMENT_COUNT.times do |i|
        GateApprovalLog.post_comment_for_pending_custom_gate_requests(installation.bot, [custom_gate_request], "this is comment #{i}")
      end

      assert_equal "closed", custom_gate_request.reload.state
      assert_equal 10, GateApprovalLog.count
      assert_equal 10, custom_gate_request.gate_approvals.count

      assert_raises_with_message(ArgumentError, "You have exceeded the maximum allowed comments of 10 for the pending approval in environment #{env.name}.") do
        GateApprovalLog.post_comment_for_pending_custom_gate_requests(installation.bot, [custom_gate_request], "this is comment 11")
      end
    end
  end
end
