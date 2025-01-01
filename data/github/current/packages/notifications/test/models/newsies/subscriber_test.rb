# typed: true
# frozen_string_literal: true

require "test_helper"

module Newsies
  class SubscriberTest < GitHub::TestCase
    context "#events" do
      test "is empty by default" do
        subscriber = Subscriber.new(1, true, false, :subscribed, Time.now)
        assert_empty subscriber.events
      end

      test "can be instantiated with an event array which is returned by #events" do
        events = %w[closed opened]
        subscriber = Subscriber.new(1, true, false, :subscribed, Time.now, events)
        assert_same_elements events, subscriber.events
      end
    end
  end
end
