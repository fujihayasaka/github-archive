# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventAttributesDependencyTest < GitHub::TestCase
  extend T::Helpers

  setup do
    Hook.stubs(:delivers_in_test?).returns(true)
  end

  class EventAttrsTestEvent < Hook::Event
    event_attr :foo, required: true
    event_attr :to_be_required, to_be_required: true
    event_attr :baz
  end

  test "sets up accessor methods for each attr" do
    event = EventAttrsTestEvent.new(
      foo: "bar",
      baz: nil,
      to_be_required: "webhooks webhooks webhooks",
    )

    assert_equal "bar", T.unsafe(event).foo
    assert_nil T.unsafe(event).baz

    T.unsafe(event).foo = "lorem"
    T.unsafe(event).baz = "ipsum"

    assert_equal "lorem", T.unsafe(event).foo
    assert_equal "ipsum", T.unsafe(event).baz
    assert_equal "webhooks webhooks webhooks", T.unsafe(event).to_be_required
  end

  test "required event attrs will raise an error if not present" do
    error = assert_raises Hook::Event::MissingRequiredAttribute do
      EventAttrsTestEvent.new(foo: nil, baz: "baz", to_be_required: "bam")
    end

    assert_match /required attribute/i, error.message
    assert_match /foo/i, error.message
    assert_equal "github-event-dispatch", error.failbot_context["app"]
  end

  test "to be required event attrs will raise an error in development if not present" do
    error = assert_raises Hook::Event::MissingToBeRequiredAttribute do
      EventAttrsTestEvent.new(foo: "bar", to_be_required: nil)
    end

    assert_match /slated to be required/, error.message
    assert_match /to_be_required/, error.message
  end

  test "to be required event attrs will be sent to Failbot in production if not present" do
    Rails.env.stubs(:production?).returns(true)
    Failbot.expects(:report).with(instance_of(Hook::Event::MissingToBeRequiredAttribute), app: "github-event-dispatch")

    EventAttrsTestEvent.new(foo: "bar", to_be_required: nil)
  end

  test "does not raise an exception for optional event attrs" do
    EventAttrsTestEvent.new(foo: "bar", baz: nil, to_be_required: "bam")
  end

  test "filters out unknown event attrs" do
    event = EventAttrsTestEvent.new(foo: "bar", to_be_required: "bam", extra: "noise")

    refute event.respond_to?(:extra)
    refute event.attributes.key?(:extra)
  end

  test "adds a default attribute for `triggered_at`" do
    time = Time.now
    event = EventAttrsTestEvent.new(
      foo: "bar",
      to_be_required: "bam",
      extra: "noise",
      triggered_at: time,
    )

    assert event.respond_to?(:triggered_at)
    assert event.attributes.key?(:triggered_at)
    assert_equal time, T.unsafe(event).triggered_at
  end

  test "adds a default attribute for delivered_hook_ids" do
    event = EventAttrsTestEvent.new(
      foo: "bar",
      to_be_required: "bam",
      extra: "noise",
    )

    assert event.respond_to?(:delivered_hook_ids)
    assert event.attributes.key?(:delivered_hook_ids)
    assert_empty T.unsafe(event).delivered_hook_ids

  end
end
