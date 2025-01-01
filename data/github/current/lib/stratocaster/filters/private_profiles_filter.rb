# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class PrivateProfilesFilter < BaseFilter
    # Filters a list of events to exclude events where the actor's profile is private
    #
    # events - Array of Stratocaster::Event items to filter in place.
    #
    # Returns an array of Stratocaster::Event items
    def self.apply(events, viewer)
      actors_by_id = User.where(id: actor_ids_for(events)).index_by(&:id)

      events.delete_if do |event|
        actor_id = actor_id_for(event)
        actor = actors_by_id[actor_id]
        actor != viewer && actor&.private_profile?
      end
    end

    def self.actor_ids_for(events)
      events.filter_map { |event| actor_id_for(event) }
    end

    def self.actor_id_for(event)
      event.sender["id"]&.to_i
    end
  end
end
