# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadDeploymentProtectionRulePayloadTest < GitHub::TestCase
  fixtures do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @owner = create :user
    @org = create :organization, name: "test-org"
    @org.add_member(@owner)
    @repo = create :repository, owner: @org, name: "test-repo"
    @env = create :environment, repository: @repo
    @gate = create :gate, environment: @env, type: :custom
    @creator = create :user
    @deployment = create :deployment, environment: @env, creator: @creator
    @check_suite = create :check_suite_for_actions_app, :with_name, repository: @repo, creator: @creator
    @check_run = create :check_run, check_suite: @check_suite, deployment: @deployment
    @gate_request = create :gate_request, gate: @gate, check_run: @check_run

    @integration = create(:integration, :with_active_hook, :with_deployment_protection_rule_event)
    @installation = make_integration_installation(integration: @integration, repository: @repo)
  end

  test "payload includes required fields" do
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)
    payload = Hook::Payload::DeploymentProtectionRulePayload.new(event)

    payload_hash = payload.to_hash

    assert_equal "requested", payload_hash[:action]
    assert_equal @env.name, payload_hash[:environment]
    assert_equal "push", payload_hash[:event]
    assert_equal "#{GitHub.api_url}/repos/test-org/test-repo/actions/runs/#{@check_suite.workflow_run.id}/deployment_protection_rule", payload_hash[:deployment_callback_url]
    assert_equal @deployment.id, payload_hash[:deployment][:id]
    assert_equal [], payload_hash[:pull_requests]
  end

  test "deployment_callback_url is nil if deliverable? is false" do
    Hook::Event::DeploymentProtectionRuleEvent.any_instance.stubs(:deliverable?).returns(false)
    event = Hook::Event::DeploymentProtectionRuleEvent.new(gate_id: @gate.id, check_run_id: @check_run.id, action: "create", specific_app_only: true)
    payload = Hook::Payload::DeploymentProtectionRulePayload.new(event)

    payload_hash = payload.to_hash
    assert_nil payload_hash[:deployment_callback_url]
  end
end
