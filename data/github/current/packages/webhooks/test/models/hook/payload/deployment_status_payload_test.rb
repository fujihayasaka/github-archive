# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadDeploymentStatusPayloadTest < GitHub::TestCase
  fixtures do
    @owner = create :user
    @org = create :organization
    @org.add_member(@owner)
    @repo = create :repository, owner: @org
    @env = create :environment, repository: @repo
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner

    @check_suite = create :check_suite_for_actions_app, :with_name, repository: @repo
    @workflow_run = @check_suite.workflow_run
    @check_run = create :check_run, check_suite: @check_suite
    @check_run.create_deployment(@env.name)
    @check_run.update_status_and_deployment_from_gates
    @deployment_status = @check_run.deployment.statuses[0]
    @event = Hook::Event::DeploymentStatusEvent.new deployment_status_id: @deployment_status.id, action: "created"
    @payload = Hook::Payload::DeploymentStatusPayload.new @event
  end

  test "v3" do
    v3 = @payload.to_hash

    assert_equal @deployment_status.id, v3[:deployment_status][:id]
    assert_equal "queued", v3[:deployment_status][:state]
    assert_equal @deployment_status.deployment.id, v3[:deployment][:id]
    assert_equal @repo.id, v3[:repository][:id]
    assert_equal @check_suite.creator_id, v3[:sender][:id]
    assert_equal [:action, :check_run, :deployment, :deployment_status, :organization, :repository, :sender, :workflow, :workflow_run], v3.keys.sort
  end

  test "job summary payload" do
    v3 = @payload.to_hash
    assert_equal @deployment_status.deployment.check_run.name, v3[:check_run][:name]
    assert_equal @deployment_status.deployment.check_run.check_suite.workflow_run.name, v3[:workflow_run][:name]
  end

  test "nil workflow_run or workflow" do
    deployment_status = create :deployment_status
    event = Hook::Event::DeploymentStatusEvent.new deployment_status_id: deployment_status.id, action: "created"
    payload = Hook::Payload::DeploymentStatusPayload.new event

    v3 = payload.to_hash
    assert_nil v3[:workflow]
    assert_nil v3[:workflow_run]
  end
end
