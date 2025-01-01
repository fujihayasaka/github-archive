# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventDeployKeyEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @repo = create(:repository)
    @key = create(:public_key, repository: @repo)
  end

  setup do
    @event_attrs = {
      repository_id: @repo.id,
      key_id: @key.id,
      action: :created,
    }
  end

  test "required attributes" do
    assert_event_required_attributes(Hook::Event::DeployKeyEvent, :repository_id, :key_id, :action)
  end

  context "#actor" do
    test "is the user who created the public key record" do
      @event_attrs[:actor_id] = @user.id
      event = Hook::Event::DeployKeyEvent.new(@event_attrs)
      assert_equal @user, event.actor
    end
  end

  context "#target_repository" do
    test "is the repo that the key was added to" do
      event = Hook::Event::DeployKeyEvent.new(@event_attrs)
      assert_equal @repo, event.target_repository
    end
  end

  context "#key" do
    test "is the public key instance that was created/deleted" do
      event = Hook::Event::DeployKeyEvent.new(@event_attrs)
      assert_equal @key, event.key
    end
  end

  context "#deliverable?" do
    test "is not deliverable without a key" do
      @event_attrs[:key_id] = 0
      event = Hook::Event::DeployKeyEvent.new(@event_attrs)
      refute event.deliverable?
    end

    test "is not deliverable without a target_repository" do
      @event_attrs[:repository_id] = 0
      event = Hook::Event::DeployKeyEvent.new(@event_attrs)
      refute event.deliverable?
    end

    test "is deliverable without an actor - delivered as Ghost user" do
      @event_attrs[:actor_id] = nil
      event = Hook::Event::DeployKeyEvent.new(@event_attrs)
      assert event.deliverable?
    end

    test "is deliverable when key, repo, and actor are present" do
      event = Hook::Event::DeployKeyEvent.new(@event_attrs)
      assert event.deliverable?
    end
  end
end
