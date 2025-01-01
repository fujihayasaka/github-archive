# typed: false
# frozen_string_literal: true

module Stratocaster
  # An specialized timeline to deal with the retrieval logic for the org_all timeline.
  #
  # The org_all timeline is a replacement for the org_members timeline. Previously, we
  # were doing fanout of the timelines to every user in an org, this means that for certain orgs
  # we were writing each event to many timelines (up to 100K for orgs like EpicGames). The result?
  # there were hundreds of millions of writes in redis per day.
  #
  # We introduced a new timeline the org_all timeline that instead of having all the events targeted
  # to each individual user in the org, has all events happening in that org, whether they are public or
  # private.
  #
  # We've seen that ~97% of the events were shared in all the timelines for the differnt user in the org
  # thus, with the new timeline, and applying a filter on retrieval, we will discard on average only 3%
  # of the events, being able to render in most of the times, identical timelines than before, with only
  # writing to one single timeline per org.
  #
  # There's a drawback tho: For orgs where there are users who see only a little portion of the events,
  # because most of the activity that happens in the org is private from their point of view, their timelines
  # won't show less events then usual, as most of the events will be discarded. We handle this corner case
  # by:
  # 1. Increasing the number of events for the new timeline (org_all) from the standard size of the colleciton
  # in redis, which is 300 elements, to 500 elements.
  #
  # 2. Mixing up this information with public org events, so in the corner case, the information discarded
  # can be backfilled with relevant, public activity happening in the org.
  #
  class OrgAllTimeline < Stratocaster::Timeline

    # the OrgAll imeline was created to replace 'org_members'. Whereas 'org_members' stores
    # a timeline per user per org, 'org_all' stores one timeline per org and relies on filtering of
    # events on retrieval based on the viewing user's permissions on the org and its repositories.
    # 'org_all' has timeline keys of the format "org:1111111". We increased the default size of
    # any timeline (300) to 500 in this timeline, so we are able to build meaningful timelines
    # even if some of the events are discarded on retrieval
    INDEX_LENGTH = 500

    attr_reader :org_timeline

    # Create an instance of the filter.
    #
    # timeline - String key representing an org_all_timeline
    # viewer   - User instance viewing the timeline
    def initialize(org_all_timeline, viewer = nil)
      @org_timeline = TimelineTypes.convert_org_all_to_org(org_all_timeline)
      super(org_all_timeline, viewer)
    end

    # For this timeline we do some fancy logic
    #
    # If after filtering the first 300 events from org_all we cannot fill a page,
    # we try to fill it with the remaining events from the org_all timeline, which is longer
    # Then a regular timeline (500 vs 300 element).
    #
    # If we still cannot fill a page, we backfill with an extra page of public events
    # which are those in the org timeline
    #
    # Return Array[Event] (also memoized in @visible_events)
    def visible_events
      return @visible_events if defined?(@visible_events)
      index = 0
      max_batches = 3
      page_size = ::Stratocaster::DEFAULT_PAGE_SIZE
      batch_size = page_size * 1.5
      slice = []
      events = []
      discarded_ids = []
      visited_event_ids = []

      while events.size < page_size && (slice.empty? || slice.size == batch_size) &&
            index < max_batches
        start_slice = index * batch_size
        slice = org_all_ids.slice(start_slice...(start_slice + batch_size)) || []

        if slice.any?
          new_events, new_discarded_ids = *filtered_events_from_ids(slice, filters: org_all_filters)
          GitHub.dogstats.distribution("stratocaster", new_events.size,
            tags: ["action:visible_events_org_all", slice_tag_for_stats(index)])
          events += new_events
          discarded_ids += new_discarded_ids
          visited_event_ids |= slice
        end

        index += 1
      end

      at_least_half_discarded = discarded_ids.size >= events.size

      if events.size < page_size && at_least_half_discarded
        slice = Set.new(public_event_ids) - visited_event_ids

        if slice.any?
          new_events, _ = *filtered_events_from_ids(slice.to_a, filters: public_filters)
          GitHub.dogstats.distribution("stratocaster", new_events.size,
            tags: ["action:visible_events_org_all", "type:fallback"])
          if events.empty? && !new_events.empty?
            GitHub.dogstats.increment("stratocaster",
              tags: ["action:visible_events_org_all", "type:public_events_only"])
          end
          events += new_events
          events = events.sort_by { |e| - e.id }
        end
      end

      @visible_events = events
    end

    def org_all_ids
      @org_all_ids ||= stratocaster_response { GitHub.stratocaster.ids(timeline) }.items
    end

    def public_event_ids
      @public_event_ids ||= stratocaster_response { GitHub.stratocaster.ids(org_timeline) }.items
    end

    def filtered_events_from_ids(ids, filters: nil)
      events = stratocaster_response { GitHub.stratocaster.ids_to_events(ids) }.items
      StratocasterEventPrefiller.new(events).preload([:senders, :repos])
      filtered = filtered_events(events, filters: filters)
      discarded_ids = events.map(&:id) - filtered.map(&:id)
      [filtered, discarded_ids]
    end

    def org_all_filters
      basic_org_filters = basic_filters + [Stratocaster::Filters::TeamMembersFilter]
      basic_org_filters += [Stratocaster::Filters::DeletedReposFilter]
      basic_org_filters += [Stratocaster::Filters::DeletedActorsFilter]
      basic_org_filters
    end

    def public_filters
      basic_filters + [Stratocaster::Filters::OrgAllEventTypesFilter]
    end

    private

    def slice_tag_for_stats(index)
      name = case index
      when 0 then "initial"
      when 1 then "second"
      when 2 then "third"
      else
        (index + 1).ordinalize # e.g., "4th"
      end
      "type:#{name}_slice"
    end
  end
end
