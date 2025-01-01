# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryEventTest < GitHub::TestCase
  def setup
    @event = create(:repository_advisory_event, :renamed)
  end

  test "creates predicate methods for all VALID_EVENTS" do
    RepositoryAdvisoryEvent::VALID_EVENTS.each do |event_name|
      predicate = "#{event_name}?".to_sym
      assert @event.respond_to?(predicate),
        "expected RepositoryAdvisoryEvent to respond to ##{event_name}?"
    end
  end

  test "VALID_EVENTS predicate methods are true if the current event matches" do
    # test on a non-matching event first
    @event.event = "foo"
    RepositoryAdvisoryEvent::VALID_EVENTS.each do |event_name|
      refute_predicate @event, "#{event_name}?".to_sym
    end

    # now matching events
    RepositoryAdvisoryEvent::VALID_EVENTS.each do |event_name|
      @event.event = event_name
      assert_predicate @event, "#{event_name}?".to_sym
    end
  end
end
