# typed: true
# frozen_string_literal: true

module Stratocaster
  class Dispatcher
    # Public: Builds an instance of Stratocaster::Dispatcher and performs
    # dispatching.
    #
    # service    - A Stratocaster::Service instance.
    # attributes - A Stratocaster::Attributes instance.
    # event_properties - Hash of Event properties.
    #              :sender  - The User that is triggering the Event.
    #              :payload - Hash of custom Event properties
    #              :url     - The String URL of the event.
    #              :repo    - The optional Repository of the Event target.
    #              :user    - The optional User owner of the Repository.
    #
    # Returns a Stratocaster::Event instance.
    def self.perform(service_instance, attr_class_instance, event_properties)
      service_instance ||= GitHub.stratocaster
      disp = new(service_instance, attr_class_instance, event_properties)
      disp.perform
    rescue Object => exception # rubocop:todo Lint/RescueException
      if exception.is_a?(Stratocaster::Error)
        raise
      else
        raise Stratocaster::Error.new(disp, exception)
      end
    end

    # Public: Builds a new instance of Stratocaster::Dispatcher.
    #
    # service    - A Stratocaster::Service instance.
    # attributes - A Stratocaster::Attributes instance.
    # event_properties - Hash of Event properties.
    #              :sender  - The User that is triggering the Event.
    #              :payload - Hash of custom Event properties
    #              :url     - The String URL of the event.
    #              :repo    - The optional Repository of the Event target.
    #              :user    - The optional User owner of the Repository.
    def initialize(service, attr_class_instance = nil, event_properties = {})
      @service = service
      @index = @service.index
      @attributes = attr_class_instance
      @perform_fanout = !event_properties.respond_to?(:delete) ||
        !event_properties.delete(:skip_dispatching)
      @event_properties = event_properties
    end

    # Public: Creates a Stratocaster::Event.
    #
    # Returns the saved Stratocaster::Event.
    def perform
      create_event if @event_properties.is_a?(Hash)
    end

    # Public: Determines if fanout should be performed for the persisted
    #         Stratocaster::Event.
    #
    # Returns a Boolean.
    def perform_fanout?
      @perform_fanout
    end

    private

    # Private: Creates the Stratocaster::Event from the event properties Hash passed
    # into the constructor.
    #
    # event_properties - Hash of Event properties.
    #              :sender  - The User that is triggering the Event.
    #              :payload - Hash of custom Event properties
    #              :targets - Array of Integer User IDs that receive this event.
    #              :url     - The String URL of the event.
    #              :repo    - The optional Repository of the Event target.
    #              :user    - The optional User owner of the Repository.
    def create_event
      event = @service.build(@event_properties)

      if perform_fanout?
        event.team_members = Stratocaster::Filters::TeamMembersFilter.team_members_for(event)
      else
        event.team_members = []
      end

      @service.create(event).tap do |event|
        if GitHub.stratocaster_event_timestamp_cache_enabled? && actor = event.sender_record
          # Cache created_at so we can look this up even if the matching
          # stratocaster_events record is deleted
          Feeds::KV.store.set(actor.stratocaster_event_timestamp_cache_key, event.created_at.utc.iso8601)
        end
      end
    end
  end
end
