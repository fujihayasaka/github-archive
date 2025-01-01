# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventInstallationTargetEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @business = create(:business)

    @integration = create(:integration, :with_active_hook, integrator_events: ["installation_target"])
  end

  context "required attributes" do
    test ":changes" do
      assert_event_required_attributes Hook::Event::InstallationTargetEvent, :changes
    end

    test ":target_id" do
      assert_event_required_attributes Hook::Event::InstallationTargetEvent, :target_id
    end

    test ":target_type" do
      assert_event_required_attributes Hook::Event::InstallationTargetEvent, :target_type
    end
  end

  context "non required attributes" do
    test ":actor_id" do
      refute_event_required_attributes Hook::Event::InstallationTargetEvent, :actor_id
    end
  end

  test "#action" do
    event = Hook::Event::InstallationTargetEvent.new(
      changes: { old_login: "old-login" },
      target_id: @user.id,
      target_type: "User"
    )

    assert_equal :renamed, event.action
  end

  context "#changes" do
    test "sets the login for a user" do
      event = Hook::Event::InstallationTargetEvent.new(
        changes: { old_login: "old-login" },
        target_id: @user.id,
        target_type: "User"
      )

      assert_same_hash({
        login: { from: "old-login" }
      }, event.changes)
    end

    test "sets the login for an org" do
      event = Hook::Event::InstallationTargetEvent.new(
        changes: { old_login: "old-login" },
        target_id: @org.id,
        target_type: "Organization"
      )

      assert_same_hash({
        login: { from: "old-login" }
      }, event.changes)
    end

    test "set the slug for a business" do
      event = Hook::Event::InstallationTargetEvent.new(
        changes: { slug_was: "old-slug" },
        target_id: @business.id,
        target_type: "Business"
      )

      assert_same_hash({
        slug: { from: "old-slug" }
      }, event.changes)
    end
  end

  context "#subscribed_hooks" do
    context "returns integrations where the target is installed" do
      test "for users" do
        make_integration_installation(integration: @integration, target: @user)

        event = Hook::Event::InstallationTargetEvent.new(
          changes: { old_login: "old-login" },
          target_id: @user.id,
          target_type: "User"
        )

        assert_equal [@integration.hook], event.subscribed_hooks
      end

      test "for orgs" do
        make_integration_installation(integration: @integration, target: @org)

        event = Hook::Event::InstallationTargetEvent.new(
          changes: { old_login: "old-login" },
          target_id: @org.id,
          target_type: "Organization"
        )

        assert_equal [@integration.hook], event.subscribed_hooks
      end

      test "for businesses" do
        integration = create(:integration, :with_active_hook, integrator_events: ["installation_target"], default_permissions: { Business::Resources.subject_types.first => :read })
        make_integration_installation(integration: integration, target: @business)

        event = Hook::Event::InstallationTargetEvent.new(
          changes: { slug_was: "old-slug" },
          target_id: @business.id,
          target_type: "Business"
        )

        assert_equal [integration.hook], event.subscribed_hooks
      end
    end

    test "does not return anything when the target does not have an installation" do
      event = Hook::Event::InstallationTargetEvent.new(
        changes: { old_login: "old-login" },
        target_id: @user.id,
        target_type: "User"
      )

      assert_empty event.subscribed_hooks
    end

    test "filters out integrations that aren't subscribed" do
      make_integration_installation(integration: @integration, target: @user)

      installation = make_integration_installation(target: @user)
      refute_includes installation.integration.integrator_events, "installation_target"

      event = Hook::Event::InstallationTargetEvent.new(
        changes: { old_login: "old-login" },
        target_id: @user.id,
        target_type: "User"
      )

      assert_equal [@integration.hook], event.subscribed_hooks
    end
  end

  context "#target" do
    test "user" do
      event = Hook::Event::InstallationTargetEvent.new(
        changes: { old_login: "old-login" },
        target_id: @user.id,
        target_type: "User"
      )

      assert_equal @user, event.target
    end

    test "organization" do
      event = Hook::Event::InstallationTargetEvent.new(
        changes: { old_login: "old-login" },
        target_id: @org.id,
        target_type: "Organization"
      )

      assert_equal @org, event.target
    end

    test "business" do
      event = Hook::Event::InstallationTargetEvent.new(
        changes: { slug_was: "old-slug" },
        target_id: @business.id,
        target_type: "Business"
      )

      assert_equal @business, event.target
    end
  end
end
