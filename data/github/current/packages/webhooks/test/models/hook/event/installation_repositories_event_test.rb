# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventInstallationRepositoriesEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @owner  = create :user, login: "owner", plan: "bronze"
    create(:private_repository, owner: @owner)

    @github_app   = create(:integration, :with_active_hook)
    @installation = make_integration_installation(integration: @github_app, target: @owner)
  end

  context "#action" do
    test "is required" do
      assert_event_required_attributes Hook::Event::InstallationRepositoriesEvent, :action
    end
  end

  context "#installation_id" do
    test "is required" do
      assert_event_required_attributes Hook::Event::InstallationRepositoriesEvent, :installation_id
    end
  end

  context "#installation" do
    test "is looked up using the installation_id" do
      event = Hook::Event::InstallationRepositoriesEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id

      assert_equal @installation, event.installation
    end
  end

  context "#actor" do
    test "is looked up using the actor_id" do
      event = Hook::Event::InstallationRepositoriesEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id

      assert_equal @owner, event.actor
    end

    test "falls back to ghost if actor_id is nil" do
      event = Hook::Event::InstallationRepositoriesEvent.new action: :created,
        actor_id: nil,
        installation_id: @installation.id

      assert_equal User.ghost, event.actor
    end

    test "falls back to ghost if actor_id references nonexistent user" do
      event = Hook::Event::InstallationRepositoriesEvent.new action: :created,
        actor_id: 123456789,
        installation_id: @installation.id

      assert_equal User.ghost, event.actor
    end
  end

  context "#subscribed_hooks" do
    test "returns the installation hook for the integration" do
      event = Hook::Event::InstallationRepositoriesEvent.new action: :created,
        installation_id: @installation.id

      assert_equal [@github_app.hook], event.subscribed_hooks
    end

    test "returns [] if the integration does not have a hook" do
      @github_app.hook.destroy

      event = Hook::Event::InstallationRepositoriesEvent.new action: :created,
        installation_id: @installation.id

      assert_empty event.subscribed_hooks
    end

    test "returns [] if the integration hook is not active" do
      @github_app.hook.update(active: false)
      @github_app.hook.reload

      refute_predicate @github_app.hook, :active?

      event = Hook::Event::InstallationRepositoriesEvent.new action: :created,
        installation_id: @installation.id

      assert_empty event.subscribed_hooks
    end

    test "returns [] if the integration is suspended" do
      @github_app.suspend(actor: create(:staff_admin_user), reason: "test")

      assert_predicate @github_app, :suspended?

      event = Hook::Event::InstallationRepositoriesEvent.new action: :created,
        installation_id: @installation.id

      assert_empty event.subscribed_hooks
    end
  end

  context "requester" do
    test "returns the user if the an id is provided" do
      requester = create(:user)

      event = Hook::Event::InstallationRepositoriesEvent.new action: :added,
        actor_id: @owner.id,
        installation_id: @installation.id,
        requester_id: requester.id

      assert_equal requester, event.requester
    end

    test "returns nil if no id is provided" do
      event = Hook::Event::InstallationRepositoriesEvent.new action: :added,
        actor_id: @owner.id,
        installation_id: @installation.id

      assert_nil event.requester
    end
  end

  context "deliverable?" do
    context "when repositories_added has records" do
      test "it returns true" do
        event = Hook::Event::InstallationRepositoriesEvent.new action: :added,
          actor_id: @owner.id,
          installation_id: @installation.id,
          repositories_added: [1]

        assert event.deliverable?
      end
    end

    context "when repositories_removed has records" do
      test "it returns true" do
        event = Hook::Event::InstallationRepositoriesEvent.new action: :added,
          actor_id: @owner.id,
          installation_id: @installation.id,
          repositories_removed: [1]

        assert event.deliverable?
      end
    end

    context "when repositories_added and repositories_removed are both empty" do
      test "it returns true" do
        event = Hook::Event::InstallationRepositoriesEvent.new action: :added,
          actor_id: @owner.id,
          installation_id: @installation.id

        refute event.deliverable?
      end
    end
  end
end
