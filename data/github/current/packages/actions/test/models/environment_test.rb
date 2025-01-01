# typed: true
# frozen_string_literal: true

require "test_helper"

class EnvironmentTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include GitHub::ComponentTestHelpers
  include HydroTestHelpers
  include BackgroundDeletesTestHelpers

  # Pass this as the `only` parameter to `assert_performed_audit_entries`
  # so we can test that we are not sending unwanted events
  # (e.g. not sending both "add" and "update" for "add").
  allowed_audit_log_events = [
    "environment.create",
    "environment.add_protection_rule",
    "environment.update_protection_rule",
    "environment.remove_protection_rule",
    "environment.delete"
  ]

  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner

    @owner = create(:user)
    @org = create(:organization)
    @org.add_member(@owner)
    @team = create(:public_team, organization: @org)
    @repo = create(:repository, owner: @org)
    @repo.add_team(@team, action: :write)
    @env = create(:environment, repository: @repo)

    @org_with_admin = create(:organization, admin: @owner)
    @repo_with_branch_policy = create(:repository, owner: @owner, organization: @org_with_admin)

    check_suite = create(:check_suite_for_actions_app, repository: @repo)
    @check_run = create(:check_run, check_suite: check_suite)
    @integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)

    @env_with_all_gates = create(:environment, repository: @repo)

    create(:gate, environment: @env_with_all_gates, type: "manual_approval")
    create(:gate, environment: @env_with_all_gates, type: "timeout")
    create(:gate, environment: @env_with_all_gates, type: "branch_policy")
    create(:gate, environment: @env_with_all_gates, type: "custom", integration_id: @integration.id)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
  end

  context "#create" do
    test "environment names are case insensitive and case preserving" do
      env = create(:environment, repository: @repo, name: "Production")

      assert_equal "Production", @repo.environments.find_by(name: "Production").name
      assert_equal "Production", @repo.environments.find_by(name: "PRODUCTION").name

      assert_raises ActiveRecord::RecordInvalid do
        create(:environment, repository: @repo, name: "production")
      end
    end

    test "creating an environment emits environment.create event" do
      GitHub.context.push(actor_id: @owner.id)

      environment_name = "production"

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        create(:environment, repository: @repo, name: environment_name)
      end

      environment = @repo.environments.find_by(name: environment_name)

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.create",
        actor: @owner.login,
        environment_name: environment.name,
        environment_id: environment.id
      }

      assert_subset_hash expected_payload, events.first
    end

    test "calling Environment.create_for_repository for a new environment emits environment.create event" do
      GitHub.context.push(actor_id: @owner.id)

      environment_name = "production"

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        Environment.create_for_repository(@repo.id, environment_name)
      end

      environment = @repo.environments.find_by(name: environment_name)

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.create",
        actor: @owner.login,
        environment_name: environment.name,
        environment_id: environment.id
      }

      assert_subset_hash expected_payload, events.first
    end

    test "calling Environment.create_for_repository for an existing environment does not emit environment.create event" do
      GitHub.context.push(actor_id: @owner.id)

      environment_name = "production"
      create(:environment, repository: @repo, name: environment_name)

      events = assert_performed_audit_entries(count: 0, only: allowed_audit_log_events) do
        Environment.create_for_repository(@repo.id, environment_name)
      end

      assert_empty events
    end
  end

  context "#latest_completed_deployment" do
    test "gets latest completed deployment" do
      newer_deployment = create :deployment, environment: @env.name, repository: @repo
      older_deployment = create :deployment, environment: @env.name, repository: @repo, created_at: newer_deployment.created_at - 42.hours
      create :deployment_status, :success, deployment: older_deployment
      create :deployment_status, :success, deployment: newer_deployment

      assert_equal @env.latest_completed_deployment, newer_deployment
    end

    test "gets latest completed deployment includes failed deployments" do
      newer_deployment = create :deployment, environment: @env.name, repository: @repo
      older_deployment = create :deployment, environment: @env.name, repository: @repo, created_at: newer_deployment.created_at - 42.hours
      create :deployment_status, :success, deployment: older_deployment
      create :deployment_status, :failure, deployment: newer_deployment

      assert_equal @env.latest_completed_deployment, newer_deployment
    end
  end

  context "#add_approver" do
    test "adds an approver to a new gate with a valid approver" do
      gate_approver = @env.add_approver(@owner)
      assert_equal @owner, gate_approver.approver
    end

    test "adds an approver to an existing gate with a valid approver" do
      gate = create(:gate, environment: @env, type: "manual_approval")
      gate_approver = @env.add_approver(@owner)
      assert_equal @owner, gate_approver.approver
      assert_equal @owner, gate.gate_approvers.first.approver
    end

    test "returns nil and adds no gate with an invalid approver" do
      rando = create(:user)
      assert_nil @env.add_approver(rando)
      assert_empty @env.gates.reload
    end

    test "adds an approver to a new gate only emits add_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.add_approver(@owner)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.add_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "manual_approval"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "adds an approver to an existing gate only emits update_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)
      gate = create(:gate, environment: @env, type: "manual_approval")

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.add_approver(@owner)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.update_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "manual_approval",
        approvers_was: [],
        approvers: [{ user:  @owner.login, user_id: @owner.id }]
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "#remove_approver" do
    test "removes an approver from the gate with other approvers" do
      user = create(:user)
      @org.add_member(user)

      assert @env.add_approver(@owner)
      assert @env.add_approver(user)

      assert @env.remove_approver(user)
      assert_equal [@owner], @env.gates.reload.first.gate_approvers.map { |ga| ga.approver }
    end

    test "removes an approver when there is no approval gate" do
      assert @env.remove_approver(@owner)
      assert_empty @env.gates.reload
    end

    test "removes a gate with no more approvers" do
      assert @env.add_approver(@owner)
      assert @env.remove_approver(@owner)
      assert_empty @env.gates.reload
    end

    test "returns true if the approver is not on the gate" do
      assert @env.remove_approver(@owner)
    end

    test "removes an approver emits update_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)
      user = create(:user)
      @org.add_member(user)
      @env.add_approver(@owner)
      @env.add_approver(user)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.remove_approver(user)
      end

      assert_equal last_performed_audit_entries, events

      events.first[:approvers_was].sort_by! { |a| a[:user_id] }

      expected_payload = {
        action: "environment.update_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "manual_approval",
        approvers_was: [
          { user: @owner.login, user_id: @owner.id },
          { user: user.login, user_id: user.id }
        ],
        approvers: [{ user:  @owner.login, user_id: @owner.id }]
      }

      assert_subset_hash expected_payload, events.first
    end

    test "removes the last approver emits remove_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)
      @env.add_approver(@owner)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.remove_approver(@owner)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.remove_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "manual_approval"
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "#create_or_update_approval_gate" do
    test "adds an approval gate with a valid approver" do
      approval_gate = @env.create_or_update_approval_gate([@owner], prevent_self_review: false)

      assert_equal "manual_approval", approval_gate.type
      assert_equal [@owner], approval_gate.gate_approvers.map(&:approver)
    end

    test "adds gate ignoring invalid approvers" do
      rando = create(:user)

      approval_gate = @env.create_or_update_approval_gate([@owner, rando], prevent_self_review: false)

      @env.valid?
      assert_equal [@owner], approval_gate.gate_approvers.map(&:approver)
    end

    test "updates an existing approval gate with valid approvers" do
      user = create(:user)
      user2 = create(:user)
      @repo.add_member(user)
      @repo.add_member(user2)

      @env.create_or_update_approval_gate([@owner, user, user2], prevent_self_review: false)

      @env.create_or_update_approval_gate([@owner], prevent_self_review: false)

      approval_gate = @env.create_or_update_approval_gate([@owner, @team], prevent_self_review: false)

      assert_equal [@owner, @team], approval_gate.gate_approvers.map(&:approver)
    end

    test "requires at least one approver" do
      approval_gate = @env.create_or_update_approval_gate([], prevent_self_review: false)

      assert_nil approval_gate
      assert_equal "Failed to create the environment protection rule. Required reviewers must have at least one reviewer.", @env.errors[:base].to_sentence
    end

    test "requires less than the max approvers" do
      approval_gate = @env.create_or_update_approval_gate((Gate::MAX_APPROVERS + 1).times.map { create(:user) }, prevent_self_review: false)

      assert_nil approval_gate
      assert_equal "Failed to create the environment protection rule. Required reviewers can have at most 6 reviewers.", @env.errors[:base].to_sentence
    end

    test "adds an approval gate only emits add_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.create_or_update_approval_gate([@owner], prevent_self_review: false)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.add_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "manual_approval"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "updates an approval gate only emits update_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)
      @env.create_or_update_approval_gate([@owner], prevent_self_review: false)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.create_or_update_approval_gate([@owner, @team], prevent_self_review: false)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.update_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "manual_approval",
        approvers_was: [{ user:  @owner.login, user_id: @owner.id }],
        approvers: [
          { user: @owner.login, user_id: @owner.id },
          { team: "#{@org.name}/#{@team.name}", team_id: @team.id },
        ]
      }

      assert_subset_hash expected_payload, events.first
    end

    test "adds an approval gate with a valid approver but prevent self review is true" do
      approval_gate = @env.create_or_update_approval_gate([@owner], prevent_self_review: true)

      assert_equal "manual_approval", approval_gate.type
      assert_equal [@owner], approval_gate.gate_approvers.map(&:approver)
      assert_equal true, approval_gate.prevent_self_review?
    end
  end

  context "#remove_approval_gate" do
    prevent_self_review = false
    test "removes existing approval gate" do
      @env.create_or_update_approval_gate([@owner], prevent_self_review: false)

      @env.remove_approval_gate

      assert_nil @env.approval_gate
    end

    test "emits remove_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)
      @env.create_or_update_approval_gate([@owner], prevent_self_review: false)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.remove_approval_gate
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.remove_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "manual_approval"
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "#create_or_update_custom_protection_rules" do
    test "adds a custom gate" do
      repo = create(:repository)
      env = create(:environment, repository: repo)
      integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      make_integration_installation(integration: integration, repository: repo)

      assert_query_count_per_table({
        gates: 2, # 1 SELECT + 1 INSERT
        integration_installations: 1,
        hook_event_subscriptions: 1,
        integrations: 1,
      }) do
        env.create_or_update_custom_protection_rules([integration.id])
      end

      assert env.gates.first.custom?
      assert_equal integration, env.gates.first.integration
    end

    test "updates multiple custom gates" do
      repo = create(:repository)
      env = create(:environment, repository: repo)
      integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      integration2 = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      integration3 = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      make_integration_installation(integration: integration, repository: repo)
      make_integration_installation(integration: integration2, repository: repo)
      make_integration_installation(integration: integration3, repository: repo)

      assert_query_count_per_table({
        gates: 3, # 1 SELECT + 2 INSERT
        integration_installations: 1,
        hook_event_subscriptions: 1,
        integrations: 2
      }) do
        env.create_or_update_custom_protection_rules([integration.id, integration2.id])
      end

      assert_equal 2, env.gates.count
      assert_equal integration, env.gates[0].integration
      assert_equal integration2, env.gates[1].integration

      assert_query_count_per_table({
        gates: 4, # 2 SELECT + 1 DELETE + 1 INSERT
        environments: 1,
        repositories: 1,
        gate_requests: 1,
        gate_approvers: 1,
        gate_branch_policies: 1,
        integration_installations: 1,
        hook_event_subscriptions: 1,
        integrations: 2
      }) do
        env.create_or_update_custom_protection_rules([integration2.id, integration3.id])
      end

      env.gates.reload

      assert_equal 2, env.gates.count
      assert_equal integration2, env.gates[0].integration
      assert_equal integration3, env.gates[1].integration
    end

    test "removes custom gates" do
      repo = create(:repository)
      env = create(:environment, repository: repo)
      integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      integration2 = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      make_integration_installation(integration: integration, repository: repo)
      make_integration_installation(integration: integration2, repository: repo)

      env.create_or_update_custom_protection_rules([integration.id, integration2.id])

      assert_equal 2, env.gates.count

      assert_query_count_per_table({
        gates: 3,
        gate_requests: 2,
        gate_approvers: 2,
        gate_branch_policies: 2,
        integrations: 2,
      }) do
        env.create_or_update_custom_protection_rules([])
      end

      assert_equal 0, env.gates.count
    end

    test "does not create custom gates for integrations that are not installed" do
      repo = create(:repository)
      env = create(:environment, repository: repo)
      integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      integration2 = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)

      # install integration but not integration2
      make_integration_installation(integration: integration, repository: repo)

      assert_query_count_per_table({
        gates: 2, # 1 SELECT + 1 INSERT
        permissions: 2,
        integration_installations: 1,
        hook_event_subscriptions: 1,
      }) do
        env.create_or_update_custom_protection_rules([integration.id, integration2])
      end

      assert_equal 1, env.gates.count
      assert_equal integration.id, env.gates.first.integration_id
    end

    test "emits add_protection_rule and remove_protection_rule events" do
      GitHub.context.push(actor_id: @owner.id)
      integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      integration2 = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      make_integration_installation(integration: integration, repository: @repo)
      make_integration_installation(integration: integration2, repository: @repo)
      @env.create_or_update_custom_protection_rules([integration.id])

      events = assert_performed_audit_entries(count: 2, only: allowed_audit_log_events) do
        @env.create_or_update_custom_protection_rules([integration2.id])
      end

      add_payload = {
        action: "environment.add_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "custom",
        integration_id: integration2.id
      }
      assert_subset_hash add_payload, events.pop
      remove_payload = {
        action: "environment.remove_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "custom",
        integration_id: integration.id
      }
      assert_subset_hash remove_payload, events.pop
    end
  end

  context "#custom_protection_rules" do
    test "returns eligible integrations and whether they are enabled as a custom protection rule" do
      # create an environment with a custom gate that will be enabled
      env = create :environment, :with_custom_gate, repository: @repo
      enabled_integration = env.gates.first.integration

      assert_query_count(8, ignore_feature_flags: true) do
        assert_equal 1, env.custom_protection_rules.count
      end

      # create an additional integration that will be disabled
      disabled_integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
      make_integration_installation(integration: disabled_integration, repository: @repo)

      # ensure that there are not n+1 queries when there are multiple integrations
      assert_query_count(5, ignore_feature_flags: true) do
        assert_equal 2, env.custom_protection_rules.count
      end

      expected = [
        { integration_id: enabled_integration.id, integration: enabled_integration, enabled: true, invalid: false },
        { integration_id: disabled_integration.id, integration: disabled_integration, enabled: false, invalid: false }
      ].sort_by { |h| h[:integration].id }
      assert_equal expected, env.custom_protection_rules.sort_by { |h| h[:integration].id }
    end

    test "returns an empty array when there are no eligible integrations" do
      env = create :environment, repository: @repo
      integration = create :integration, :with_active_hook # does not subscribe to the deployment_protection_rule event
      make_integration_installation(integration: integration, repository: @repo)

      assert_query_count(4, ignore_feature_flags: true) do
        assert_equal 0, env.custom_protection_rules.count
      end
    end

    test "returns invalid rules when integration is deleted" do
      env = create :environment, :with_custom_gate, repository: @repo
      integration = env.custom_gates.first.integration
      integration.destroy

      assert_query_count(8, ignore_feature_flags: true) do
        rules = env.custom_protection_rules
        assert_equal 1, rules.count
        assert_equal integration.id, rules.first[:integration_id]
        assert_nil rules.first[:integration]
        assert rules.first[:enabled]
        assert rules.first[:invalid]
      end
    end

    test "returns both invalid and valid rules when an integration is deleted" do
      env = create :environment, :with_custom_gate, repository: @repo
      integration = env.custom_gates.first.integration
      integration_id = integration.id
      integration2 = create :integration, :with_active_hook, :with_deployment_protection_rule_event
      integration2_id = integration2.id
      make_integration_installation(integration: integration2, repository: @repo)
      env.create_or_update_custom_protection_rules([integration_id, integration2_id])

      assert_equal 2, env.custom_protection_rules.count

      integration.destroy

      assert_query_count(5, ignore_feature_flags: true) do
        rules = env.custom_protection_rules
        assert_equal 2, rules.count
        invalid = rules.find { |r| r[:integration_id] == integration_id }
        valid = rules.find { |r| r[:integration_id] == integration2_id }

        assert_equal integration_id, invalid[:integration_id]
        assert_equal integration2_id, valid[:integration_id]
        assert_equal integration, invalid[:integration]
        assert_equal integration2, valid[:integration]
        assert invalid[:enabled]
        assert valid[:enabled]
        assert invalid[:invalid]
        refute valid[:invalid]
      end
    end

    test "returns invalid rules when integration is uninstalled" do
      env = create :environment, :with_custom_gate, repository: @repo
      integration = env.custom_gates.first.integration

      perform_enqueued_jobs only: [DestroyDependentRecordsJob] do
        integration.installations.destroy_all
      end

      assert_query_count(5, ignore_feature_flags: true) do
        rules = env.custom_protection_rules
        assert_equal 1, rules.count
        assert_equal integration.id, rules.first[:integration_id]
        assert_equal integration, rules.first[:integration]
        assert rules.first[:enabled]
        assert rules.first[:invalid]
      end
    end

    test "returns invalid rules when integration is suspended" do
      env = create :environment, :with_custom_gate, repository: @repo
      integration = env.custom_gates.first.integration
      installation = integration.installations.first
      installation.suspend!

      assert_query_count(8, ignore_feature_flags: true) do
        rules = env.custom_protection_rules
        assert_equal 1, rules.count
        assert_equal integration.id, rules.first[:integration_id]
        assert_equal integration, rules.first[:integration]
        assert rules.first[:enabled]
        assert rules.first[:invalid]
      end
    end

    test "returns invalid rules when integration no longer subscribes to the deployment_protection_rule event" do
      env = create :environment, :with_custom_gate, repository: @repo
      integration = env.custom_gates.first.integration
      integration.installations.first.event_records.destroy_all # does not subscribe to the deployment_protection_rule event

      assert_query_count(8, ignore_feature_flags: true) do
        rules = env.custom_protection_rules
        assert_equal 1, rules.count
        assert_equal integration.id, rules.first[:integration_id]
        assert_equal integration, rules.first[:integration]
        assert rules.first[:enabled]
        assert rules.first[:invalid]
      end
    end
  end

  context "environment pinning" do
    test "environment is not pinned" do
      env = create :environment, repository: @repo
      assert_not env.is_pinned?
    end

    test "environment is pinned" do
      env = create :environment, repository: @repo
      pinned = PinnedEnvironment.create(repository: @repo, environment_id: env.id)
      assert env.is_pinned?
    end

    test "pinned_position returns the correct position" do
      env = create :environment, repository: @repo
      pinned = PinnedEnvironment.create(repository: @repo, environment_id: env.id, position: 1)
      assert_equal 1, env.pinned_position
    end

    test "pinned_position retuns null if the env is not pinned" do
      env = create :environment, repository: @repo
      assert_nil env.pinned_position
    end
  end

  context "custom app integrations" do
    test "returns only disabled apps that are installed on the repo" do
      owner = create(:user)
      org = create(:organization)
      org.add_member(owner)
      repo = create(:repository, owner: org)
      env = create :environment, repository: repo
      # integration is a custom gates app installed on the repo with an existing gate
      integration_with_gate = create(:integration, :with_active_hook, :with_deployment_protection_rule_event, name: "app-with-gate")
      make_integration_installation(integration: integration_with_gate, repositories: [repo])
      create(:gate, environment: env, type: "custom", integration_id: integration_with_gate.id)

      # custom gates integration without an existing gate that is not installed on repo
      another_repo = create(:repository, owner: org)
      integration_not_installed = create(:integration, :with_active_hook, :with_deployment_protection_rule_event, name: "not-installed-app")
      make_integration_installation(integration: integration_not_installed, repositories: [another_repo])

      # custom gates integration without an existing gate that is installed on repo
      installed_disabled_integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event, name: "installed-app")
      make_integration_installation(integration: installed_disabled_integration, repositories: [repo])
      # second_installation = make_integration_installation(integration: @second_integration, target: @org, permissions: { "deployments" => :write }, events: ["deployment_protection_rule"])

      assert_query_count(6, ignore_feature_flags: true) do
        assert_equal 1, env.available_disabled_custom_gate_apps.count
      end
      # create an additional disabled integration installed on the repo
      installed_disabled_integration_2 = create(:integration, :with_active_hook, :with_deployment_protection_rule_event, name: "additional-disabled-app")
      make_integration_installation(integration: installed_disabled_integration_2, repositories: [repo])

      # create an additional disabled integration installed on the repo
      installed_disabled_integration_3 = create(:integration, :with_active_hook, :with_deployment_protection_rule_event, name: "another-additional-disabled-app")
      make_integration_installation(integration: installed_disabled_integration_3, repositories: [repo])

      # ensure that there are not n+1 queries when there are multiple integrations
      assert_query_count(5, ignore_feature_flags: true) do
        assert_equal 3, env.available_disabled_custom_gate_apps.count
      end

      assert_includes env.available_disabled_custom_gate_apps, installed_disabled_integration
      assert_includes env.available_disabled_custom_gate_apps, installed_disabled_integration_2
      assert_includes env.available_disabled_custom_gate_apps, installed_disabled_integration_3
    end

    test "returns empty array if there are no installations for the repo" do
      owner = create(:user)
      org = create(:organization)
      org.add_member(owner)
      repo = create(:repository, owner: org)
      env = create :environment, repository: repo

      assert_empty env.available_disabled_custom_gate_apps
    end
  end

  context "#create_or_update_wait_gate" do
    test "adds a wait gate" do
      wait_gate = @env.create_or_update_wait_gate(42)

      assert_equal "timeout", wait_gate.type
      assert_equal 42, wait_gate.timeout
    end

    test "adds a wait gate only emits add_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.create_or_update_wait_gate(23)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.add_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "timeout"
      }

      assert_subset_hash expected_payload, events.first
    end

    test "updates an existing wait gate with new timeout" do
      @env.create_or_update_wait_gate(42)

      wait_gate = @env.create_or_update_wait_gate(23)

      assert_equal 23, wait_gate.timeout
    end

    test "updates an existing wait gate only emits update_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)
      @env.create_or_update_wait_gate(42)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.create_or_update_wait_gate(23)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.update_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "timeout",
        timeout_was: 42,
        timeout: 23
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "#remove_wait_gate" do
    test "removes existing wait gate" do
      @env.create_or_update_wait_gate(42)

      @env.remove_wait_gate

      assert_nil @env.wait_gate
    end

    test "emits remove_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)
      @env.create_or_update_wait_gate(42)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.remove_wait_gate
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.remove_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "timeout"
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "#create_branch_policy_gate" do
    test "adds a branch policy gate with the appropriate type" do
      branch_gate = @env.create_branch_policy_gate(protected_branch_policy: true)

      assert_equal "branch_policy", branch_gate.type
      assert_equal true, @env.reload.branch_policy_gate_branch_protected?
    end

    test "Changes branch policy type if gate type is changed" do
      branch_gate = @env.create_branch_policy_gate(protected_branch_policy: true)
      assert_equal "branch_policy", branch_gate.type
      assert_equal true, @env.reload.branch_policy_gate_branch_protected?

      branch_gate = @env.create_branch_policy_gate(protected_branch_policy: false)
      assert_equal "branch_policy", branch_gate.type
      assert_equal false, @env.reload.branch_policy_gate_branch_protected?
    end

    test "adding then changing a branch policy type first emits add, then update events" do
      GitHub.context.push(actor_id: @owner.id)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.create_branch_policy_gate(protected_branch_policy: true)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.add_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "branch_policy",
        is_protected_branch_policy: true
      }

      assert_subset_hash expected_payload, events.first

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.create_branch_policy_gate(protected_branch_policy: false)
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.update_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "branch_policy"
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "#remove_branch_policy_gate" do
    test "removes existing branch policy gate" do
      @env.create_branch_policy_gate(protected_branch_policy: true)

      refute_nil @env.reload.branch_policy_gate

      @env.remove_branch_policy_gate

      assert_nil @env.reload.branch_policy_gate
    end

    test "emits remove_protection_rule event" do
      GitHub.context.push(actor_id: @owner.id)
      @env.create_branch_policy_gate(protected_branch_policy: true)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        @env.remove_branch_policy_gate
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.remove_protection_rule",
        actor: @owner.login,
        environment_name: @env.name,
        environment_id: @env.id,
        gate_type: "branch_policy"
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "#destroy" do
    prevent_self_review = false
    test "it destroys an environment" do
      as @owner
      env = create(:environment, :with_approval_gate, repository: @repo)
      assert env.gates.size > 0

      env.destroy

      assert env.destroyed?
      assert_equal 0, env.gates.size
    end

    test "destroy! succeeds" do
      env = create(:environment, :with_approval_gate, repository: @repo)
      env.destroy!
      assert env.destroyed?
    end

    test "it rejects any pending gate request on the environment" do
      as @owner
      env = create(:environment, :with_approval_gate, repository: @repo)
      gate = env.approval_gate
      gate_request = GateRequest.create_or_update_gate_request(gate, @check_run, "token", :closed)

      env.destroy

      assert env.destroyed?
      assert_equal "rejected", gate_request.reload.state
    end

    test "it sends hydro events to clean up secrets" do
      as @owner
      env = create(:environment, repository: @repo)

      env.destroy

      env_next_global_id = env.global_relay_id
      unless GitHub.enterprise?
        env_next_global_id = env.next_global_id
      end

      assert_hydro_published({
        actor: Hydro::EntitySerializer.user(@owner),
        deleted_environment: Hydro::EntitySerializer.environment(env, overrides: { next_global_id: env_next_global_id })
      }, schema: "github.v1.EnvironmentDeleted")
    end

    test "it queues NotifyRejectedGatesJob for any rejected gate requests" do
      as @owner
      env = create(:environment, :with_approval_gate, repository: @repo)
      gate = env.approval_gate
      gate_request = create(:gate_request, gate: gate, state: :closed)

      NotifyRejectedGatesJob.expects(:perform_later).with(gate_request_ids: [gate_request.id], repository_global_relay_id: @repo.global_relay_id, gate_global_relay_id: gate.global_relay_id)

      env.destroy
    end

    test "it queues BatchInactivateDeploymentsJob when environment is destroyed" do
      org = create :business_plus_org
      repo = create :private_repository, owner: org
      env = create :environment, repository: repo

      BatchInactivateDeploymentsJob.expects(:perform_later).with(repository_id: env.repository.id, environment: env.name)

      env.destroy!
    end

    test "Inactivating a deployment does not re-create the environment" do
      as @owner
      GitHub.stubs(:actions_enabled?).returns(true)
      org = create :business_plus_org
      repo = create :private_repository, owner: org
      env = create :environment, repository: repo
      deployment = create :deployment, repository: repo, environment: env.name
      deployment_status = create :deployment_status, deployment: deployment, state: "success"

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob, BatchInactivateDeploymentsJob]) do
        env.destroy
      end

      # Find by name since the re-created environment wouldn't necessarily have the same ID.
      assert Environment.find_by(name: env.name).nil?
    end

    test "it instruments an event" do
      as @owner
      env = create(:environment, repository: @repo)
      env.create_or_update_approval_gate([@owner], prevent_self_review: false)

      events = assert_performed_audit_entries(count: 1, only: allowed_audit_log_events) do
        env.destroy
      end

      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "environment.delete",
        actor: @owner.login,
        environment_name: env.name,
      }

      assert_subset_hash expected_payload, events.first
    end

    test "also destroys associated pinned environments" do
      first_env = create(:environment, repository: @repo)
      second_env = create(:environment, repository: @repo)

      first_pin = create(:pinned_environment, environment: first_env)
      second_pin = create(:pinned_environment, environment: second_env)

      @repo.reload
      assert_equal 4, @repo.environments.count
      assert_equal 2, @repo.pinned_environments.count
      assert_equal 2, @repo.pinned_environments.count
      assert @repo.pinned_environments.include?(first_pin)
      assert @repo.pinned_environments.include?(second_pin)

      first_env.destroy
      @repo.reload
      assert_equal 3, @repo.environments.count
      assert_equal 1, @repo.pinned_environments.count
      assert_equal second_pin, @repo.pinned_environments.first

      @env.destroy
      @repo.reload
      assert_equal 2, @repo.environments.count
      assert_equal 1, @repo.pinned_environments.count
      assert_equal second_pin, @repo.pinned_environments.first

      second_env.destroy
      @repo.reload
      assert_equal 1, @repo.environments.count
      assert_equal 0, @repo.pinned_environments.count
    end
  end

  context "#create_for_repository" do
    test "it creates an environment with a default name" do
      repo = create(:repository)

      Environment.create_for_repository(repo.id, nil)

      refute_nil repo.environments.find_by(name: "production")
    end

    test "it creates an environment with an input name" do
      repo = create(:repository)

      Environment.create_for_repository(repo.id, "my_env_name")

      refute_nil repo.environments.find_by(name: "my_env_name")
    end

    test "it strips whitespace from an environment name" do
      repo = create(:repository)

      Environment.create_for_repository(repo.id, "   my_env_name   ")

      refute_nil repo.environments.find_by(name: "my_env_name")
    end

    test "it ignores environments that already exist" do
      repo = create(:repository)
      original_env = create(:environment, repository: repo, name: "my_env_name", created_at: 1.day.ago, updated_at: 1.day.ago)

      Environment.create_for_repository(repo.id, "my_env_name")

      env = repo.environments.find_by(name: "my_env_name")
      refute_nil env
      assert_equal original_env.updated_at, env.updated_at
    end

    test "allows high unicode in environment names" do
      repo = create(:repository)
      env = Environment.new(repository_id: repo.id, name: "🥑Toast")

      assert_predicate env, :valid?, "should be valid with high unicode in name"

      assert_nothing_raised do
        create :environment, name: "🥑Toast", repository_id: repo.id
      end
    end

    test "produces an error with an invalid environment name" do
      repo = create(:repository)

      env = Environment.new(repository_id: repo.id, name: "morethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255charsmorethan255chars")
      assert_equal false, env.valid?

      env = Environment.new(repository_id: repo.id, name: "~")
      assert_equal false, env.valid?

      env = Environment.new(repository_id: repo.id, name: ".")
      assert_equal false, env.valid?

      env = Environment.new(repository_id: repo.id, name: "..")
      assert_equal false, env.valid?

      env = Environment.new(repository_id: repo.id, name: "hello\nthere")
      assert_equal false, env.valid?

      env = Environment.new(repository_id: repo.id, name: "hello\rthere")
      assert_equal false, env.valid?

      env = Environment.new(repository_id: repo.id, name: "hello there \u0007")
      assert_equal false, env.valid?

      Environment::INVALID_NAME_CHARS.each do |char|
        env = Environment.new(repository_id: repo.id, name: "hello #{char} there")
        assert_equal false, env.valid?, "Expected env to not be valid with #{char.inspect} in the name"
      end
    end
  end

  context "#create_or_update_environment" do
    test "creates a new environment with all the gates" do
      environment_json = {
        "wait_timer": 20,
        "reviewers": [
          {
            "type": "User",
            "id": @owner.id
          }
        ],
        "deployment_branch_policy": {
          "protected_branches": true,
          "custom_branch_policies": false
        }
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "unittest-env"
      environment = Environment.create_or_update_environment(@repo_with_branch_policy, environment_data, environment_name)

      assert_equal environment_name, environment["name"]
    end

    test "creates a new environment and strips spaces from name" do
      environment_json = {
        "wait_timer": 20,
        "reviewers": [
          {
            "type": "User",
            "id": @owner.id
          }
        ],
        "deployment_branch_policy": {
          "protected_branches": true,
          "custom_branch_policies": false
        }
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "   unittest-env-spaces "
      environment = Environment.create_or_update_environment(@repo_with_branch_policy, environment_data, environment_name)

      assert_equal environment_name.strip, environment["name"]
    end

    test "updates environment" do
      environment_json = {
        "wait_timer": 20
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "unittest-env"
      @repo.owner.plan.stubs(:actions_eligible?).returns(true)
      environment = Environment.create_or_update_environment(@repo, environment_data, environment_name)

      assert_equal 20, environment.gates[0].timeout
      assert_equal environment_name, environment["name"]

      environment_json = {
        "wait_timer": 40
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment = Environment.create_or_update_environment(@repo, environment_data, environment_name)

      assert_equal 40, environment.gates[0].timeout
      assert_equal environment_name, environment["name"]
    end

    test "returns error when wait_timer exceeds limit" do
      # Gate::MAX_TIMEOUT_MINUTES is 43200
      environment_json = {
        "wait_timer": 43201,
        "reviewers": [
          {
            "type": "User",
            "id": @owner.id
          }
        ],
        "deployment_branch_policy": {
          "protected_branches": true,
          "custom_branch_policies": false
        }
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "unittest-env"

      assert_raises Environment::EnvironmentError do
        environment = Environment.create_or_update_environment(@repo, environment_data, environment_name)
      end
    end

    test "does not return error when reviewers is empty" do
      @repo.owner.plan.stubs(:actions_eligible?).returns(true)
      environment_json = {
        "reviewers": [],
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "unittest-env"

      environment = Environment.create_or_update_environment(@repo, environment_data, environment_name)
    end

    test "returns error when reviewers exceeds limit" do
      users = [*1..6].map { |_i| { type: "User", id: create(:user).id } }

      environment_json = {
        "reviewers": [
          {
            "type": "User",
            "id": @owner.id
          }
        ].concat(users),
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "unittest-env"

      assert_raises Environment::EnvironmentError do
        environment = Environment.create_or_update_environment(@repo, environment_data, environment_name)
      end
    end

    test "honours wait_timer" do
      environment_json = {
        "wait_timer": 40
      }.to_json
      @repo.owner.plan.stubs(:actions_eligible?).returns(true)
      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "unittest-env"
      environment = Environment.create_or_update_environment(@repo, environment_data, environment_name)

      assert_equal "timeout", environment.gates[0].type
      assert_equal 40, environment.gates[0].timeout
    end

    test "honours reviewers" do
      environment_json = {
        "reviewers": [
          {
            "type": "User",
            "id": @owner.id
          }
        ]
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "unittest-env"

      @repo.owner.plan.stubs(:actions_eligible?).returns(true)
      environment = Environment.create_or_update_environment(@repo, environment_data, environment_name)

      assert_equal "manual_approval", environment.gates[0].type
      assert_equal "User", environment.gates[0].gate_approvers[0].approver_type
      assert_equal @owner.id, environment.gates[0].gate_approvers[0].approver_id
    end

    test "honours deployment branch policy - protected_branches" do
      environment_json = {
        "deployment_branch_policy": {
          "protected_branches": true,
          "custom_branch_policies": false
        }
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "unittest-env"
      environment = Environment.create_or_update_environment(@repo_with_branch_policy, environment_data, environment_name)

      expected_body = {
        "protected_branches": true
      }.to_json.to_s

      assert_equal "branch_policy", environment.gates[0].type
      assert_equal expected_body, environment.gates[0].body
    end

    test "honours deployment branch policy - custom_branch_policies" do
      environment_json = {
        "deployment_branch_policy": {
          "protected_branches": false,
          "custom_branch_policies": true
        }
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "unittest-env"
      environment = Environment.create_or_update_environment(@repo_with_branch_policy, environment_data, environment_name)

      expected_body = {
        "protected_branches": false
      }.to_json.to_s

      assert_equal "branch_policy", environment.gates[0].type
      assert_equal expected_body, environment.gates[0].body
    end

    test "returns error when both protected_branches and custom_branch_policies are set true" do
      environment_json = {
        "deployment_branch_policy": {
          "protected_branches": true,
          "custom_branch_policies": true
        }
      }.to_json

      environment_data = GitHub::JSON.parse(environment_json)
      environment_name = "unittest-env"
      assert_raises Environment::EnvironmentError do
        environment = Environment.create_or_update_environment(@repo_with_branch_policy, environment_data, environment_name)
      end
    end
  end

  context "#gates" do
    test "returns all gates when repo is enterprise" do
      @env_with_all_gates.repository.stubs(:can_use_deployment_branch_gates?).returns(true)

      assert_equal 4, @env_with_all_gates.gates.count
    end

    test "returns only branch_policy gates when repo is team/pro" do
      @env_with_all_gates.repository.stubs(:can_use_deployment_branch_gates?).returns(false)
      @env_with_all_gates.repository.stubs(:can_use_deployment_protected_branch?).returns(true)

      assert_equal 1, @env_with_all_gates.gates.count
      assert_equal "branch_policy", @env_with_all_gates.gates[0].type
    end

    test "returns all gates when repo flags aren't set" do
      # to ensure that tests with no repository level stubs still work
      assert_equal 4, @env_with_all_gates.gates.count
    end
  end

  test "is deleted with repository" do
    other_env = create(:environment, repository: @repo_with_branch_policy)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [@env, @env_with_all_gates]
      config.expect_not_destroyed = [other_env]
    end
  end
end
