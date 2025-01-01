# typed: false
# frozen_string_literal: true

module Stratocaster
  class Mysql2Store
    def query_options
      GitHub.dogstats.increment("stratocaster.store.query_options")
      nil
    end

    # Public: Get an event by a key.
    #
    # key - String or Integer Event ID.
    #
    # Returns a Stratocaster::Event.
    def get(key)
      Model.get(key)
    end

    # Public: Get multiple events by a list of keys.
    #
    # *keys - One or more String/Integer Event IDs.
    #
    # Returns an Array of Stratocaster::Events, in the order the keys are provided
    def get_all(*keys)
      Model.get_all(*keys)
    end

    # Public: Saves the event.  Creates it if the event has no ID.
    #
    # event - A Stratocaster::Event, or something really similar.
    #
    # Returns the saved Stratocaster::Event.
    def save(event)
      if event.id
        set event.id, event
      else
        create event
      end
    end

    # Internal: Creates an Event without an existing ID.
    #
    # event - A Stratocaster::Event, or something really similar.
    #
    # Returns the saved Stratocaster::Event.
    def create(event)
      if event.id
        raise ArgumentError, "Cannot re-create an Event, use #set instead: #{event.class} ##{event.id}"
      end

      Model.create_from_event!(event).to_event
    end

    # Public: Saves an Event.
    #
    # key   - A String or Integer Event ID.
    # event - A Stratocaster::Event.
    #
    # Returns the saved Stratocaster::Event.
    def set(key, event)
      GitHub.dogstats.increment("stratocaster.store.set")
      if event.id.to_s != key.to_s
        raise ArgumentError, "Key #{key} does not match #{event.class} ##{event.id}"
      end

      Model.find(key).tap do |m|
        m.update_from_event!(event)
      end.to_event
    end

    # Public: Deletes an Event.
    #
    # key - A String or Integer Event ID.
    #
    # Returns nothing.
    def delete(key)
      GitHub.dogstats.increment("stratocaster.store.delete")
      delete_all(key)
    end

    # Public: Deletes Events.
    #
    # key - An Array of String/Integer Event IDs.
    #
    # Returns nothing.
    def delete_all(*keys)
      Model.delete(keys)
    end
  end
end
