# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventInstallationEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @owner  = create :user, login: "owner"

    @github_app   = create(:integration, :with_active_hook)
    @installation = make_integration_installation(integration: @github_app, repository: create(:repository, owner: @owner))
  end

  test "attributes required" do
    assert_event_required_attributes Hook::Event::InstallationEvent,
    :action,
    :installation_id,
    :integration_id,
    :actor_id
  end

  test "attributes not required" do
    refute_event_required_attributes Hook::Event::InstallationEvent, :requester_id
  end

  context "#installation" do
    test "is looked up using the installation_id" do
      event = Hook::Event::InstallationEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id,
        integration_id: @github_app.id

      assert_equal @installation, event.installation
    end
  end

  context "#actor" do
    test "is looked up using the actor_id" do
      event = Hook::Event::InstallationEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id,
        integration_id: @github_app.id

      assert_equal @owner, event.actor
    end
  end

  context "#integration" do
    test "is looked up using integration_id" do
      Integration.expects(:find).once.with(@github_app.id).returns(@github_app)
      event = Hook::Event::InstallationEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id,
        integration_id: @github_app.id

      assert_equal @github_app, event.integration
    end
  end

  context "#requester" do
    test "is looked up using the requester_id" do
      requester = create(:user)

      event = Hook::Event::InstallationEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id,
        requester_id: requester.id,
        integration_id: @github_app.id

      assert_equal requester, event.requester
    end
  end

  context "#subscribed_hooks" do
    test "returns the installation hook for the integration" do
      event = Hook::Event::InstallationEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id,
        integration_id: @github_app.id

      assert_equal [@github_app.hook], event.subscribed_hooks
    end

    test "returns [] if the integration does not have a hook" do
      @github_app.hook.destroy
      @github_app.reload

      event = Hook::Event::InstallationEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id,
        integration_id: @github_app.id

      assert_empty event.subscribed_hooks
    end

    test "returns [] if the integration hook is not active" do
      @github_app.hook.update(active: false)
      @github_app.hook.reload

      refute_predicate @github_app.hook, :active?

      event = Hook::Event::InstallationEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id,
        integration_id: @github_app.id

      assert_empty event.subscribed_hooks
    end

    test "returns [] if the integration is suspended" do
      @github_app.suspend(actor: create(:staff_admin_user), reason: "test")

      assert_predicate @github_app, :suspended?

      event = Hook::Event::InstallationEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id,
        integration_id: @github_app.id

      assert_empty event.subscribed_hooks
    end
  end

  context "#repository_selection" do
    test "returns the selection type for the installation" do
      event = Hook::Event::InstallationEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id,
        integration_id: @github_app.id

      assert_equal "selected", event.repository_selection
    end
  end

  context "#repositories" do
    test "returns the repositories for an installation" do
      event = Hook::Event::InstallationEvent.new action: :created,
        actor_id: @owner.id,
        installation_id: @installation.id,
        integration_id: @github_app.id

      assert_kind_of ActiveRecord::Relation, event.repositories
    end
  end
end
