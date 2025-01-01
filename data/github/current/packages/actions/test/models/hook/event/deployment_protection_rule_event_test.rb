# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventDeploymentProtectionRuleEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @owner = create :user
    @org = create :organization
    @org.add_member(@owner)
    @repo = create :repository, owner: @org
    @env = create :environment, repository: @repo
    @integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
    @installation = make_integration_installation(integration: @integration, repository: @repo)
    @gate = create :gate, environment: @env, type: :custom, integration_id: @integration.id
    @creator = create :user
    @check_suite = create :check_suite_for_actions_app, :with_name, repository: @repo, creator: @creator
    @check_run = create :check_run, check_suite: @check_suite
    @gate_request = create :gate_request, gate: @gate, check_run: @check_run

    @repo2 = create :repository, owner: @org
    @env2 = create :environment, repository: @repo2
    @gate2 = create :gate, environment: @env2, type: :custom, integration_id: @integration.id
    @check_suite2 = create :check_suite_for_actions_app, :with_name, repository: @repo2, creator: @creator
    @check_run2 = create :check_run, check_suite: @check_suite2
    @gate_request2 = create :gate_request, gate: @gate2, check_run: @check_run2
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::DeploymentProtectionRuleEvent, :specific_app_only, :gate_id, :check_run_id, :action
  end

  test "returns target repository" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)
    assert_equal @repo, event.target_repository
  end

  test "returns actor" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)
    assert_equal @creator, event.actor
  end

  test "returns deliverable?" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)
    assert_equal true, event.deliverable?

    check_suite = create :check_suite, :with_name, repository: @repo, creator: @creator
    check_run = create :check_run, check_suite: check_suite
    gate = create :gate, environment: @env, type: :custom
    gate_request = create :gate_request, gate: gate, check_run: check_run
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: gate.id, check_run_id: check_run.id, action: "create", specific_app_only: true)
    assert_equal false, event.deliverable?
  end

  test "returns integration" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create",  specific_app_only: true)
    assert_equal @integration, event.integration
  end

  test "returns subscribed_hooks" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create",  specific_app_only: true)
    assert_includes event.subscribed_hooks, @integration.hook
  end

  test "returns no subscribed_hooks when integration hooks are inactive" do
    @integration.hook.disable
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create",  specific_app_only: true)
    assert_equal [], event.subscribed_hooks
  end

  test "returns no subscribed_hooks when integration is disabled" do
    @integration.suspend(actor: create(:staff_admin_user), reason: "test")

    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create",  specific_app_only: true)
    assert_equal [], event.subscribed_hooks
  end

  test "returns no subscribed_hooks when integration has no access to repository" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate2.id, check_run_id: @check_run2.id, action: "create",  specific_app_only: true)
    assert_equal [], event.subscribed_hooks
  end

  test "returns no subscribed_hooks when integration unsubscribed from deployment_protection_rule webhook" do
    @installation.events = %w()
    @installation.save!
    assert_predicate @installation.events, :empty?

    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create",  specific_app_only: true)
    assert_equal [], event.subscribed_hooks
  end

  test "returns subscribed_installations_for" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)
    assert_includes event.subscribed_installations_for(@integration.id), @installation
    assert_equal event.subscribed_installations_for(@integration.id).count, 1
  end

  test "returns subscribed installations with multiple installations" do
    make_integration_installation(repository: @repo2, permissions: { "metadata" => :read })
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)

    assert_includes event.subscribed_installations_for(@integration.id), @installation
    assert_equal event.subscribed_installations_for(@integration.id).count, 1
  end

  test "returns no subscribed installations when integration is suspended" do
    @integration.suspend(actor: create(:staff_admin_user), reason: "test")

    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)
    assert_equal [], event.subscribed_installations_for(@integration.id)
  end

  test "returns gate" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)
    assert_equal @gate, event.gate
  end

  test "returns check_run" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)
    assert_equal @check_run, event.check_run
  end

  test "returns workflow_run" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)
    assert_equal @check_suite.workflow_run, event.workflow_run
  end

  test "returns deployment_callback_url" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)

    api_url = GitHub.api_url
    repo = @repo.name_with_display_owner
    workflow_run_id = @check_suite.workflow_run.id

    assert_equal "#{api_url}/repos/#{repo}/actions/runs/#{workflow_run_id}/deployment_protection_rule",
                 event.deployment_callback_url
  end
end
