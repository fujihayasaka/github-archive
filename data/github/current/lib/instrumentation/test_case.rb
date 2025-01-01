# typed: true
# frozen_string_literal: true

require "instrumentation/test_subscription"

module Instrumentation
  class TestCase
    attr_reader :subscriptions

    def initialize(service)
      @instrumentation_service = service
      @subscriptions = []
    end

    def subscription_class
      @subscription_class ||= TestSubscription
    end
    attr_writer :subscription_class

    def instrumentation_service
      @instrumentation_service ||= GitHub.instrumentation_service
    end
    attr_writer :instrumentation_service

    def reset_subscriptions
      subscriptions.each do |sub|
        sub.unsubscribe
      end
      subscriptions.clear
    end

    def reset_events
      subscriptions.each do |sub|
        sub.reset_events
      end
    end

    def subscribe(pattern)
      subscription = subscription_class.new(instrumentation_service)
      subscription.subscribe(pattern)
      subscriptions << subscription
      subscription.events
    end
  end
end
