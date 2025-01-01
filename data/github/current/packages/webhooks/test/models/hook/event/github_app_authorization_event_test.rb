# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventGitHubAppAuthorizationEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @authorized_user = create(:user, login: "authorized-user")
    @github_app      = create(:integration, :with_active_hook)
  end

  context "#action" do
    test "is required" do
      assert_event_required_attributes Hook::Event::GitHubAppAuthorizationEvent, :action
    end
  end

  context "#actor_id" do
    test "is required" do
      assert_event_required_attributes Hook::Event::GitHubAppAuthorizationEvent, :actor_id
    end
  end

  context "#integration_id" do
    test "is required" do
      assert_event_required_attributes Hook::Event::GitHubAppAuthorizationEvent, :integration_id
    end
  end

  context "#actor" do
    test "is looked up using the actor_id" do
      event = Hook::Event::GitHubAppAuthorizationEvent.new(
        action:         :revoked,
        actor_id:       @authorized_user.id,
        integration_id: @github_app.id,
      )

      assert_equal @authorized_user, event.actor
    end
  end

  context "#deliverable?" do
    test "is false if the actor is nil" do
      @authorized_user.destroy

      event = Hook::Event::GitHubAppAuthorizationEvent.new(
        action:         :revoked,
        actor_id:       @authorized_user.id,
        integration_id: @github_app.id,
      )

      refute_predicate event, :deliverable?
    end

    test "is false if integration is nil" do
      @github_app.destroy

      event = Hook::Event::GitHubAppAuthorizationEvent.new(
        action:         :revoked,
        actor_id:       @authorized_user.id,
        integration_id: @github_app.id,
      )

      refute_predicate event, :deliverable?
    end
  end

  context "#subscribed_hooks" do
    test "returns the installation hook for the integration" do
      event = Hook::Event::GitHubAppAuthorizationEvent.new(
        action:         :revoked,
        actor_id:       @authorized_user.id,
        integration_id: @github_app.id,
      )

      assert_equal [@github_app.hook], event.subscribed_hooks
    end

    test "returns an empty array if the integration has been destroyed" do
      @github_app.destroy

      event = Hook::Event::GitHubAppAuthorizationEvent.new(
        action:         :revoked,
        actor_id:       @authorized_user.id,
        integration_id: @github_app.id,
      )

      assert_empty event.subscribed_hooks
    end

    test "returns an empty array if the integration hook is not active" do
      @github_app.hook.update(active: false)
      @github_app.hook.reload

      refute_predicate @github_app.hook, :active?

      event = Hook::Event::GitHubAppAuthorizationEvent.new(
        action:         :revoked,
        actor_id:       @authorized_user.id,
        integration_id: @github_app.id,
      )

      assert_empty event.subscribed_hooks
    end

    test "returns an empty array if the integration is suspended" do
      @github_app.suspend(actor: create(:staff_admin_user), reason: "test")

      assert_predicate @github_app, :suspended?

      event = Hook::Event::GitHubAppAuthorizationEvent.new(
        action:         :revoked,
        actor_id:       @authorized_user.id,
        integration_id: @github_app.id,
      )

      assert_empty event.subscribed_hooks
    end
  end
end
