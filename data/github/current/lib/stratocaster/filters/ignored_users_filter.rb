# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class IgnoredUsersFilter < BaseFilter
    # Filters a list of events based on who the user has ignored.
    #
    # events - Array of Stratocaster::Event items to filter in place.
    #
    # Returns an Array of Stratocaster::Event items
    def self.apply(events, viewer)
      ignored_user_ids = ignored_user_ids_from_events(events, viewer)

      events.delete_if do |event|
        actor_id = actor_id_for(event)
        target_id = event.target_id

        if target_id
          ignored_user_ids.include?(actor_id) || ignored_user_ids.include?(target_id)
        else
          ignored_user_ids.include?(actor_id)
        end
      end
    end

    # Private: Given an array of Stratocaster::Event items, return a set
    # of User ids that should be ignored.
    #
    # events - Array of Stratocaster::Event items
    #
    # Returns a Set of User#id Integers
    def self.ignored_user_ids_from_events(events, viewer)
      actor_ids = events.map { |event| actor_id_for(event) }
      target_ids = events.map { |event| event.target_id }.compact
      relevant_user_ids = actor_ids | target_ids

      Set.new(viewer.ignoring_in(relevant_user_ids).map(&:id))
    end

    def self.actor_id_for(event)
      event.sender["id"].to_i
    end
  end
end
