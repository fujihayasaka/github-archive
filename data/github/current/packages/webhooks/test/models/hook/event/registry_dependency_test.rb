# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventRegistryDependencyTest < GitHub::TestCase
  class EventRegistryTestEvent < Hook::Event
    supports_targets Repository, Organization
    display_name "event"
    description "Sample event for testing only."
  end

  class EventRegistryTest2Event < Hook::Event
    supports_targets Repository, Organization
    description "Another sample event for testing only."
  end

  class FeatureFlaggedEventRegistryTestEvent < Hook::Event
    supports_targets Repository, Organization
    description "Feature Flagged Sample event for testing only."
    feature_flag :preview_features?
  end

  class BusinessEventRegistryTestEvent < Hook::Event
    supports_targets Business
    description "Business Sample event for testing only."
  end

  context ".event_type" do
    test "parses the event type from the class name" do
      assert_equal "event_registry_test", EventRegistryTestEvent.event_type
    end
  end

  context ".supports_target?" do
    test "returns true if the event supports the target instance" do
      assert EventRegistryTestEvent.supports_target?(Repository.new)
      assert EventRegistryTestEvent.supports_target?(Organization.new)
      assert BusinessEventRegistryTestEvent.supports_target?(Business.new)
    end

    test "returns false if the event doesn't support the target instance" do
      refute EventRegistryTestEvent.supports_target?(Business.new)
      refute BusinessEventRegistryTestEvent.supports_target?(Repository.new)
    end
  end

  context ".inherited" do
    test "registers the event class" do
      assert_includes Hook::EventRegistry.event_classes, EventRegistryTestEvent
    end
  end

  context ".display_name" do
    test "returns the specified display name" do
      assert_equal "event", EventRegistryTestEvent.display_name
    end

    test "defaults to humanized event_type" do
      assert_equal "event registry test2s", EventRegistryTest2Event.display_name
    end
  end

  context ".description" do
    test "returns the specified description" do
      assert_equal "Sample event for testing only.", EventRegistryTestEvent.description
    end
  end

  context ".feature_flag" do
    test "returns the specified feature flag" do
      assert_nil EventRegistryTestEvent.feature_flag
      assert_equal :preview_features?, FeatureFlaggedEventRegistryTestEvent.feature_flag
    end
  end

  context ".feature_flagged?" do
    test "returns whether or not the event has a feature flag" do
      assert FeatureFlaggedEventRegistryTestEvent.feature_flagged?
      refute EventRegistryTestEvent.feature_flagged?
    end
  end
end
