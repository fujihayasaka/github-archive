# typed: true
# frozen_string_literal: true

require "active_support/notifications"

module Audit
  class Event < ActiveSupport::Notifications::Event
    # Public: Wrap ActiveSupport::Notifications::Event classes and sub-classes with the
    # Audit::Event class for access to context payload merging. Currently used to populate test
    # events fully.
    #
    # events - An Array of AS::Notifications::Event objects.
    #
    # Returns an Array of Audit::Event objects.
    def self.wrap(events = [])
      events.map do |event|
        new(
          event.name,
          event.time,
          event.end,
          event.transaction_id,
          GitHub.audit.build_payload(event.name, event.payload),
        )
      end
    end

    # Public: The event's Context.
    #
    # This is used to merge into the final payload.
    #
    # Returns a Context object.
    def context
      @context ||= Audit.context
    end
    attr_writer :context

    # Public: The audit event payload.
    #
    # Merges the Context and a Hash of event information (including timing).
    #
    # Returns a payload Hash.
    def payload
      @merged_payload ||= context.merge(@payload)
    end
  end
end
