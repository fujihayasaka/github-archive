# typed: true
# frozen_string_literal: true

require "test_helper"

class SuperStealthEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Secret event that only preview users can see"
  feature_flag :preview_hook_events
end

class PartiallyExposedEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Secret event that only preview users can see"
  feature_flag :preview_hook_events, actions: [:created]
end

class VisibilityPerTargetEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Secret event that only preview users can see"
  feature_flag :preview_hook_events

  def self.visible_for(user, target)
    GitHub.flipper[:preview_hook_events].enabled?(target)
  end
end

class HookEventRegistryTest < GitHub::TestCase
  fixtures do
    @hook = create(:hook)
    @regular_user = create(:user)
    @preview_user = preview_user
    enable_feature_flag(:preview_hook_events, @preview_user)
  end

  context ".visible_to_user" do
    test "filters out events the users is NOT feature flagged for" do
      refute @regular_user.preview_features?
      filtered = Hook::EventRegistry.visible_to_user([Hook::Event::PushEvent, SuperStealthEvent], @regular_user)

      assert_includes filtered, Hook::Event::PushEvent
      refute_includes filtered, SuperStealthEvent
    end

    test "continues to include events that only have some events flagged" do
      refute @regular_user.preview_features?

      events    = [Hook::Event::PushEvent, PartiallyExposedEvent]
      filtered  = Hook::EventRegistry.visible_to_user(events, @regular_user)

      assert_includes filtered, Hook::Event::PushEvent
      assert_includes filtered, PartiallyExposedEvent
      refute_includes filtered, SuperStealthEvent
    end

    test "includes events the user is feature flagged for" do
      assert @preview_user.preview_features?
      filtered = Hook::EventRegistry.visible_to_user([Hook::Event::PushEvent, SuperStealthEvent], @preview_user)

      assert_includes filtered, Hook::Event::PushEvent
      assert_includes filtered, SuperStealthEvent
    end
  end

  context ".subscribable_by" do
    test "filters out events the user is not feature flagged for" do
      refute @regular_user.preview_features?
      filtered = Hook::EventRegistry.subscribable_by(hook: @hook, user: @regular_user)

      assert_includes filtered, Hook::Event::PushEvent
      refute_includes filtered, SuperStealthEvent
    end

    test "includes events that only have some actions flagged" do
      refute @regular_user.preview_features?

      filtered = Hook::EventRegistry.subscribable_by(hook: @hook, user: @regular_user)

      assert_includes filtered, Hook::Event::PushEvent
      assert_includes filtered, PartiallyExposedEvent
      refute_includes filtered, SuperStealthEvent
    end

    test "includes events the user is feature flagged for" do
      assert @preview_user.preview_features?
      filtered = Hook::EventRegistry.subscribable_by(hook: @hook, user: @preview_user)

      assert_includes filtered, Hook::Event::PushEvent
      assert_includes filtered, SuperStealthEvent
    end

    test "respects custom visiblity on events" do
      enable_feature_flag(:preview_hook_events, @hook.installation_target)
      assert @preview_user.preview_features?
      filtered = Hook::EventRegistry.subscribable_by(hook: @hook, user: @preview_user)

      assert_includes filtered, VisibilityPerTargetEvent
    end
  end

  context ".for_event_type" do
    test "looks up a registered event by its event_type" do
      assert_equal Hook::Event::PushEvent, Hook::EventRegistry.for_event_type("push")
      assert_equal Hook::Event::PushEvent, Hook::EventRegistry.for_event_type(:push)
    end

    test "returns nil if it can't find the Hook::Event" do
      assert_nil Hook::EventRegistry.for_event_type("unknown")
    end
  end
end
