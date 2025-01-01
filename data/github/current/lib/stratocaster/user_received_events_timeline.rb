# typed: true
# frozen_string_literal: true

module Stratocaster
  # This is the timeline that is used when you do an API call to `/users/:username/received_events`
  # and are authenticated as :username. If you are not authenticated as that user then we don't fall
  # into here and instead show you a generic Timeline for the `user:[id]:public` index.
  #
  # See https://developer.github.com/v3/activity/events/#list-events-that-a-user-has-received
  # See https://github.com/github/github/issues/103711#issuecomment-445363523
  #
  # This is functionally the same as Stratocaster::HomepageAllTimeline the only difference is in the
  # filters that are applied at the end of #visible_events.
  #
  class UserReceivedEventsTimeline < Stratocaster::Timeline
    def initialize(user_received_events_timeline, viewer = nil)
      @homepage_all_timeline = TimelineTypes.convert_user_received_events_timeline_to_homepage_all(
        user_received_events_timeline,
      )
      @homepage_public_timeline = TimelineTypes.convert_homepage_all_to_homepage_public(@homepage_all_timeline)
      super(@homepage_all_timeline, viewer)
    end

    def visible_events
      return @visible_events if defined?(@visible_events)
      limited_sorted_event_ids = sorted_event_ids.first(::Stratocaster::DEFAULT_INDEX_SIZE)

      events = stratocaster_response { GitHub.stratocaster.ids_to_events(limited_sorted_event_ids) }.items
      StratocasterEventPrefiller.new(events).preload(:senders)

      @visible_events = filtered_events(events, filters: basic_filters)
    end

    private

    def sorted_event_ids
      homepage_all_and_public_event_ids.uniq.sort.reverse
    end

    def homepage_all_and_public_event_ids
      homepage_all_timeline_event_ids = event_ids(timeline_key: @homepage_all_timeline)
      homepage_public_timeline_event_ids = event_ids(timeline_key: @homepage_public_timeline)
      homepage_all_timeline_event_ids.concat(homepage_public_timeline_event_ids)
    end

    def event_ids(timeline_key:)
      stratocaster_response { GitHub.stratocaster.ids(timeline_key) }.items
    end
  end
end
