# typed: false
# frozen_string_literal: true

module Instrumentation
  class TestSubscription
    class Event < ActiveSupport::Notifications::Event
    end

    attr_reader :events, :subscription

    def initialize(service = nil)
      @instrumentation_service = service
      @events = []
    end

    def instrumentation_service
      @instrumentation_service ||= GitHub.instrumentation_service
    end

    def self.subscriptions
      @subscriptions ||= []
    end

    def self.reset_subscriptions
      subscriptions.each do |subscription|
        subscription.unsubscribe
      end
      subscriptions.clear
    end

    def self.reset_events
      subscriptions.each do |subscription|
        subscription.reset_events
      end
    end

    def reset_events
      @events.clear
    end

    def self.subscribe(pattern, service = nil)
      subscription = new(service).subscribe(pattern)
      subscriptions << subscription
      subscription.events
    end

    def subscribe(pattern)
      @subscription = instrumentation_service.subscribe pattern, self
      self
    end

    def unsubscribe
      instrumentation_service.unsubscribe @subscription
    end

    def call(*args)
      event = Event.new(*args)
      events << event
    end
  end
end
