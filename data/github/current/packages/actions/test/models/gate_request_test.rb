# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/launch_test_helpers"

class GateRequestTest < GitHub::TestCase
  include HydroTestHelpers
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

    make_trusted_oauth_apps_owner
    actions_app = create :launch_integration
    GitHub.stubs(:launch_github_app).returns(actions_app)
    actions_installation = make_integration_installation(integration: actions_app, repository: @repo)

    ref = @repo.heads.read("master")
    commit = ref.append_commit({ message: "some change", committer: @owner }, @org) do |files|
      files.add("blah.txt", "some contents")
    end
    head_sha = @repo.ref_to_sha("master")

    check_suite = create(:check_suite_for_actions_app, repository: @repo, head_sha: head_sha, head_branch: "master")
    @check_run = create(:check_run, check_suite: check_suite)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)  # enables Actions for Enterprise too
  end

  # we can't use mock_notify_gate helper for branch policy gates
  # because they are immediately evaluated once the gate_request is created
  def make_branch_policy_gate_request(env, repo, check_run, is_open:)
    GitHub::Launch::Services::Environment::NotifyGateRequest.new({
      repository_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo.global_relay_id),
      gate_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: env.branch_policy_gate.global_relay_id),
      external_job_id: check_run.external_id,
      external_id: check_run.check_suite.external_id,
      is_open: is_open,
      token: "1234abcd",
      check_suite_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: check_run.check_suite.global_relay_id),
    })
  end

  context "#create_or_update_gate_request" do
    test "check run updates to 'waiting' during create gate request" do
      token = "1234abcd"
      gate = create(:gate, environment: @env)

      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, token, nil)

      assert_equal "waiting", @check_run.reload.status
      refute_nil gate_request.id
      assert gate_request.closed?
      assert_equal token, gate_request.token
    end

    test "Gate request cannot be closed if it's rejected" do
      token = "1234abcd"
      gate = create(:gate, environment: @env)

      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, token, :rejected)
      assert gate_request.rejected?

      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, token, :closed)
      assert gate_request.rejected?

      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, token, "closed")
      assert gate_request.rejected?
    end

    test "Gate request is rejected if we are closing and received conclusion" do
      token = "1234abcd"
      gate = create(:gate, environment: @env)

      # Start with closed state, not concluded yet
      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, token, :closed)
      refute gate_request.rejected?

      # Now it's concluded and closed (as symbol)
      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, token, :closed, true)
      assert gate_request.rejected?

      # Now it's concluded and closed (as string)
      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, token, "closed", true)
      assert gate_request.rejected?
    end

    test "gate request rejected based on branch policy gate" do
      token = "1234abcd"
      env = create(:environment, :with_branch_policy_gate, repository: @repo)

      request = make_branch_policy_gate_request(env, @repo, @check_run, is_open: false)

      mock_notify_gate_with_request(request:)

      gate_request = GateRequest.create_or_update_gate_request(env.branch_policy_gate, @check_run, token, nil)

      refute_nil gate_request.id
      assert_equal token, gate_request.token
      assert gate_request.rejected?
    end

    test "gate request open based on branch policy gate" do
      token = "1234abcd"
      env = create(:environment, :with_branch_policy_gate, repository: @repo)
      env.branch_policy_gate.branch_policies.create!(name: "master", repository: env.repository)

      request = make_branch_policy_gate_request(env, @repo, @check_run, is_open: true)
      mock_notify_gate_with_request(request:)

      gate_request = GateRequest.create_or_update_gate_request(env.branch_policy_gate, @check_run, token, nil)

      refute_nil gate_request.id
      assert_equal token, gate_request.token
      assert gate_request.open?
    end

    test "gate request rejected based on protected branch policy gate" do
      token = "1234abcd"
      @repo.protected_branches.create!(name: "another-branch", creator: @owner)
      env = create(:environment, :with_protected_branch_policy_gate, repository: @repo)
      assert env.branch_policy_gate_branch_protected?

      request = make_branch_policy_gate_request(env, @repo, @check_run, is_open: false)
      mock_notify_gate_with_request(request:)

      gate_request = GateRequest.create_or_update_gate_request(env.branch_policy_gate, @check_run, token, nil)

      refute_nil gate_request.id
      assert_equal token, gate_request.token
      assert gate_request.rejected?
    end

    test "gate request open based on protected branch policy gate" do
      token = "1234abcd"
      @repo.protected_branches.create!(name: "master", creator: @owner)
      env = create(:environment, :with_protected_branch_policy_gate, repository: @repo)
      assert env.branch_policy_gate_branch_protected?

      request = make_branch_policy_gate_request(env, @repo, @check_run, is_open: true)
      mock_notify_gate_with_request(request:)

      gate_request = GateRequest.create_or_update_gate_request(env.branch_policy_gate, @check_run, token, nil)

      refute_nil gate_request.id
      assert_equal token, gate_request.token
      assert gate_request.open?
    end

    test "gate request open based on tag policy gate" do
      repo = create(:private_repository, owner: @org)

      token = "1234abcd"
      env = create(:environment, :with_branch_policy_gate, repository: repo)
      env.branch_policy_gate.branch_policies.create!(name: GateBranchPolicy::PROTECTED_TAG_PREFIX + "releases/v**", repository: env.repository)

      tag_check_suite = create(:check_suite_for_actions_app, repository: repo, head_branch: "refs/tags/releases/v1")
      tag_check_run = create(:check_run, check_suite: tag_check_suite)

      request = make_branch_policy_gate_request(env, repo, tag_check_run, is_open: true)
      mock_notify_gate_with_request(request:)

      gate_request = GateRequest.create_or_update_gate_request(env.branch_policy_gate, tag_check_run, token, nil)

      refute_nil gate_request.id
      assert_equal token, gate_request.token
      assert gate_request.open?
    end

    test "gate request rejected based on tag policy gate" do
      repo = create(:private_repository, owner: @org)

      token = "1234abcd"
      env = create(:environment, :with_branch_policy_gate, repository: repo)
      env.branch_policy_gate.branch_policies.create!(name: GateBranchPolicy::PROTECTED_TAG_PREFIX + "releases/v**", repository: env.repository)

      tag_check_suite = create(:check_suite_for_actions_app, repository: repo, head_branch: "v1.1")
      tag_check_run = create(:check_run, check_suite: tag_check_suite)

      request = make_branch_policy_gate_request(env, repo, tag_check_run, is_open: false)
      mock_notify_gate_with_request(request:)

      gate_request = GateRequest.create_or_update_gate_request(env.branch_policy_gate, tag_check_run, token, nil)

      refute_nil gate_request.id
      assert_equal token, gate_request.token
      assert gate_request.rejected?
    end

    test "backfills gate approval logs for timeout gate postbacks with state approved" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      timeout_gate = create(:gate, environment: @env, type: "timeout")
      timeout_gate_request = create(:gate_request, gate: timeout_gate, state: :closed, check_run: check_run)

      GateRequest.create_or_update_gate_request(timeout_gate, check_run, "1234", "open", true)

      timeout_gate_request.reload
      gate_approval = timeout_gate_request.gate_approvals.first
      gate_approval_log = gate_approval.gate_approval_log

      assert gate_approval
      assert gate_approval_log
      assert_equal "approved", gate_approval&.state
      assert_equal "approved", gate_approval_log&.state
    end

    test "does not backfill timeout gate approval logs if gate request is not open" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      timeout_gate = create(:gate, environment: @env, type: "timeout")
      timeout_gate_request = create(:gate_request, gate: timeout_gate, state: :closed, check_run: check_run)

      GateRequest.create_or_update_gate_request(timeout_gate, check_run, "1234", "closed", false)

      timeout_gate_request.reload
      gate_approval = timeout_gate_request.gate_approvals.first

      refute gate_approval
    end

    test "does not backfill timeout gate approval logs if gate request state does not change" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      timeout_gate = create(:gate, environment: @env, type: "timeout")
      timeout_gate_request = create(:gate_request, gate: timeout_gate, state: :open, check_run: check_run)

      GateRequest.create_or_update_gate_request(timeout_gate, check_run, "1234", "open", false)

      timeout_gate_request.reload
      gate_approval = timeout_gate_request.gate_approvals.first

      refute gate_approval
    end

    test "does not backfill gate approval logs if gate approvals already exist" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      timeout_gate = create(:gate, environment: @env, type: "timeout")
      timeout_gate_request = create(:gate_request, gate: timeout_gate, state: :closed, check_run: check_run)

      GateRequest.create_or_update_gate_request(timeout_gate, check_run, "1234", "open", true)

      timeout_gate_request.reload
      assert_equal 1, timeout_gate_request.gate_approvals.size
      assert timeout_gate_request.gate_approvals.first.gate_approval_log

      # call it again to see if it creates duplicate approval logs
      GateRequest.create_or_update_gate_request(timeout_gate, check_run, "1234", "open", true)

      timeout_gate_request.reload
      assert_equal 1, timeout_gate_request.gate_approvals.size
      assert timeout_gate_request.gate_approvals.first.gate_approval_log
    end

    test "does not backfill gate approval logs if gate request is not a timeout" do
      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      not_timeout_gate = create(:gate, environment: @env, type: "manual_approval")
      not_timeout_gate_request = create(:gate_request, gate: not_timeout_gate, state: :closed, check_run: check_run)

      GateRequest.create_or_update_gate_request(not_timeout_gate, check_run, "1234", "open", true)

      # in the real world gate approval logs would be created for a manual approval gate, but we just want to validate
      # that we don't backfill any additional
      not_timeout_gate_request.reload
      assert_equal 0, not_timeout_gate_request.gate_approvals.size

    end

    test "it still saves the gate_request if token is missing" do
      # in actions four nines, we won't have a token anymore

      check_suite = create(:check_suite_for_actions_app, repository: @repo)
      check_run = create(:check_run, check_suite: check_suite)

      gate = create(:gate, environment: @env, type: "manual_approval")

      gate_request = GateRequest.create_or_update_gate_request(gate, check_run, nil, "closed", false)

      assert_equal "closed", gate_request.state
      assert_equal "", gate_request.token
    end
  end

  context "#approval_status" do
    test "returns nil when the user is not an approver" do
      gate = create(:gate, environment: @env)
      gate_request = create(:gate_request, gate: gate)

      refute gate_request.approval_status(@owner)
    end

    test "returns 'pending' when the user is a pending approver" do
      [@owner, @team].each do |approver|
        gate_approver = @env.add_approver(approver)
        gate = gate_approver.gate
        gate_request = create(:gate_request, gate: gate)

        assert_equal "pending", gate_request.approval_status(@owner)
      end
    end

    test "returns waiting when the user is an approver but cannot self approve" do
      token = "1234abcd"
      gate = create(:gate, environment: @env)
      gate_approver = @env.add_approver(@owner)
      gate = gate_approver.gate
      gate.prevent_self_review = true
      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, token, nil)

      assert_equal "waiting", @check_run.reload.status
      refute_nil gate_request.id
      assert gate_request.closed?
      assert_equal token, gate_request.token
    end

    test "returns 'approved' when the user already approved the gate request" do
      [@owner, @team].each do |approver|
        gate_approver = @env.add_approver(approver)
        gate = gate_approver.gate
        gate_request = create(:gate_request, gate: gate)
        create(:gate_approval, gate_request: gate_request, user: @owner, approver: approver, state: "approved")

        assert_equal "approved", gate_request.reload.approval_status(@owner)
      end
    end

    test "returns 'rejected' when the user already rejected the gate request" do
      [@owner, @team].each do |approver|
        gate_approver = @env.add_approver(approver)
        gate = gate_approver.gate
        gate_request = create(:gate_request, gate: gate)
        create(:gate_approval, gate_request: gate_request, user: @owner, approver: approver, state: "rejected")

        assert_equal "rejected", gate_request.reload.approval_status(@owner)
      end
    end

    test "returns nil when the approver is deleted" do
      [@owner, @team].each do |approver|
        gate_approver = @env.add_approver(approver)
        gate = gate_approver.gate
        gate_request = create(:gate_request, gate: gate)
        gate_approver.destroy

        refute gate_request.approval_status(@owner)
      end
    end

    test "returns 'pending' when the bot is an approver and has not reviewed the gate request" do
      env = create(:environment, :with_custom_gate, repository: @repo)
      gate = env.gates.first
      installation = gate.integration.installations.first

      gate_request = create(:gate_request, gate: gate)

      assert_equal "pending", gate_request.reload.approval_status(installation.bot)
    end

    test "returns nil when the bot is not an approver" do
      env = create(:environment, :with_custom_gate, repository: @repo)
      gate = env.gates.first

      # create a separate installation for a separate integration
      integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      installation = make_integration_installation(integration: integration, repository: @repo)

      gate_request = create(:gate_request, gate: gate)

      assert_nil gate_request.reload.approval_status(installation.bot)
    end

    test "returns state when the bot already reviewed the gate request" do
      env = create(:environment, :with_custom_gate, repository: @repo)
      gate = env.gates.first
      installation = gate.integration.installations.first

      %w[approved rejected].each do |state|
        gate_request = create(:gate_request, gate: gate)
        create(:gate_approval, gate_request: gate_request, user: installation.bot, approver: installation.bot, state: state)

        assert_equal state, gate_request.reload.approval_status(installation.bot)
      end
    end
  end

  context "Notifications" do

    context "#approver_ids" do
      test "returns empty array when there are no approver_ids" do
        gate = create(:gate, environment: @env)
        gate_request = create(:gate_request, gate: gate)

        assert_empty gate_request.approver_ids
      end

      test "returns owner as approver when they are set as an approver" do
        gate_approver = @env.add_approver(@owner)
        gate = gate_approver.gate
        gate_request = create(:gate_request, gate: gate)

        assert_equal [@owner.id], gate_request.approver_ids
      end

      test "returns team members as approver_ids when they are set as an approver" do
        other_user = create(:user)
        @org.add_member(other_user)
        @team.add_member other_user
        gate_approver = @env.add_approver(@team)
        gate = gate_approver.gate
        gate_request = create(:gate_request, gate: gate)

        assert_equal [@owner.id, other_user.id], gate_request.approver_ids
      end
    end

    context "#workflow_run" do
      test "workflow_run refers to the check_run's workflow_run" do
        check_suite = create(:check_suite_for_actions_app, repository: @repo)
        check_run = create(:check_run, :success, check_suite: check_suite)
        gate = create(:gate, :approval, environment: @env)
        gate_request = GateRequest.create_or_update_gate_request(gate, check_run, "token", nil)
        assert gate_request.workflow_run.present?
        assert_equal gate_request.workflow_run, check_run.check_suite.workflow_run
      end
    end

    context "#requires_manual_action?" do
      test "non-manual gate never requires action" do
        check_suite = create(:check_suite_for_actions_app, repository: @repo)
        check_run = create(:check_run, :success, check_suite: check_suite)
        gate = create(:gate, environment: @env, type: :timeout)

        refute GateRequest.create_or_update_gate_request(gate, check_run, "token", nil).requires_manual_action?
      end

      test "a manual gate requires action when it's closed" do
        check_suite = create(:check_suite_for_actions_app, repository: @repo)
        check_run = create(:check_run, :success, check_suite: check_suite)
        gate = create(:gate, :approval, environment: @env)

        assert GateRequest.create_or_update_gate_request(gate, check_run, "token", nil).requires_manual_action?
      end

      test "a manual does not requires action when it's not closed" do
        check_suite = create(:check_suite_for_actions_app, repository: @repo)
        check_run = create(:check_run, :success, check_suite: check_suite)
        gate = create(:gate, :approval, environment: @env)
        gate_request = GateRequest.create_or_update_gate_request(gate, check_run, "token", nil)

        gate_request.update(state: :open)
        refute gate_request.requires_manual_action?

        gate_request.update(state: :rejected)
        refute gate_request.requires_manual_action?
      end
    end
  end

  context "#instrument_creation" do
    test "publishes a GateRequestCreated event" do
      env = create(:environment, :with_approval_gate, name: "Staging", repository: @repo)
      gate = env.gates.find_by(type: "manual_approval")
      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, "token", "closed", nil)

      assert_hydro_published({
        gate_request_id: gate_request.id,
        gate_id: gate.id,
        gate_type: "MANUAL_APPROVAL",
        check_suite_id: @check_run.check_suite.id,
        check_run_id: @check_run.id,
        repository: Hydro::EntitySerializer.repository(@repo),
        integration: Hydro::EntitySerializer.integration(gate.integration)
      }, schema: "github.actions.v0.GateRequestCreated")
    end

    test "publishes a GateRequestCreated event with integration" do
      env = create(:environment, :with_custom_gate, name: "Staging", repository: @repo)
      gate = env.gates.find_by(type: "custom")
      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, "token", "closed", nil)

      assert_hydro_published({
        gate_request_id: gate_request.id,
        gate_id: gate.id,
        gate_type: "CUSTOM",
        check_suite_id: @check_run.check_suite.id,
        check_run_id: @check_run.id,
        repository: Hydro::EntitySerializer.repository(@repo),
        integration: Hydro::EntitySerializer.integration(gate.integration)
      }, schema: "github.actions.v0.GateRequestCreated")
    end
  end
end
