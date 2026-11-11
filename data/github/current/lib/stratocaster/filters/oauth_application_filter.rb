# typed: true
# frozen_string_literal: true

module Stratocaster::Filters
  class OauthApplicationFilter < BaseFilter
    # Filters a list of events based on organization OAuth Application policy.
    #
    # events - Array of Stratocaster::Event items to filter in place.
    def self.apply(events, viewer)
      event_org_ids = org_ids_for_events(events)

      visible_org_ids = Organization.
                          oauth_app_policy_met_by(viewer.oauth_application).
                          where(id: event_org_ids).
                          pluck(:id)

      events.select do |event|
        event.public? ||
          event.org.blank? ||
          visible_org_ids.include?(event.org["id"].to_i)
      end
    end

    # Private: Get the ids of all associated orgs for the given events.
    #
    # events - Array of Stratocaster::Event items
    #
    # Returns an Array of organization IDs.
    def self.org_ids_for_events(events)
      ids = events.map { |event| event.org && event.org["id"] }
      ids.compact!
      ids.uniq!
      ids
    end
  end
end
