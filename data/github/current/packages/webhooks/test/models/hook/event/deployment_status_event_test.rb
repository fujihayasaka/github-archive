# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventDeploymentStatusEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @deployment_status = create :deployment_status
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::DeploymentStatusEvent, :deployment_status_id
  end

  context "#deployment_status" do
    test "returns the specified status record" do
      event = Hook::Event::DeploymentStatusEvent.new deployment_status_id: @deployment_status.id, action: "created"
      assert_equal @deployment_status, event.deployment_status
    end
  end

  context "#target_repository" do
    test "returns the repo for specified status" do
      event = Hook::Event::DeploymentStatusEvent.new deployment_status_id: @deployment_status.id, action: "created"
      assert_equal @deployment_status.repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the user who created the specified status" do
      event = Hook::Event::DeploymentStatusEvent.new deployment_status_id: @deployment_status.id, action: "created"
      assert_equal @deployment_status.creator, event.actor
    end
  end

  context "#action" do
    test "returns the action for the specified deployment status" do
      event = Hook::Event::DeploymentStatusEvent.new deployment_status_id: @deployment_status.id, action: "created"
      assert_equal "created", event.action
    end
  end
end
