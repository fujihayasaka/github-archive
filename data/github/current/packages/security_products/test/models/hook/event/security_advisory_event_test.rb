# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventSecurityAdvisoryEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @security_advisory = create(:security_advisory)
  end

  test "action is required" do
    assert_event_required_attributes(Hook::Event::SecurityAdvisoryEvent, :action)
  end

  test "security_advisory_id is required" do
    assert_event_required_attributes(Hook::Event::SecurityAdvisoryEvent, :security_advisory_id)
  end

  test "action returns the correct value" do
    event = Hook::Event::SecurityAdvisoryEvent.new(
      action: :published,
      security_advisory_id: @security_advisory.id,
    )

    assert_equal :published, event.action
  end

  test "security_advisory returns the correct record" do
    event = Hook::Event::SecurityAdvisoryEvent.new(
      action: :published,
      security_advisory_id: @security_advisory.id,
    )

    assert_equal @security_advisory, event.security_advisory
  end

  test "actor returns nil" do
    event = Hook::Event::SecurityAdvisoryEvent.new(
      action: :published,
      security_advisory_id: @security_advisory.id,
    )

    assert_nil event.actor
  end
end
