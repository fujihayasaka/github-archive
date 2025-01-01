# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventDeploymentEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @deployment = create :deployment
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::DeploymentEvent, :deployment_id
  end

  context "#deployment" do
    test "returns the specified deployment" do
      event = Hook::Event::DeploymentEvent.new(deployment_id: @deployment.id, action: "created")
      assert_equal @deployment, event.deployment
    end
  end

  context "#target_repository" do
    test "returns the repository for the specified deployment" do
      event = Hook::Event::DeploymentEvent.new(deployment_id: @deployment.id, action: "created")
      assert_equal @deployment.repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the creator for the specified deployment" do
      event = Hook::Event::DeploymentEvent.new(deployment_id: @deployment.id, action: "created")
      assert_equal @deployment.creator, event.actor
    end
  end

  context "#action" do
    test "returns the action for the specified deployment" do
      event = Hook::Event::DeploymentEvent.new(deployment_id: @deployment.id, action: "created")
      assert_equal "created", event.action
    end
  end
end
