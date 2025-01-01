# typed: true
# frozen_string_literal: true

module Stratocaster
  class HomepageAllTimeline < Stratocaster::Timeline

    attr_reader :homepage_public_timeline

    # Create an instance of the timeline.
    #
    # timeline - String key representing an homepage_all_timeline
    # viewer   - User instance viewing the timeline
    def initialize(homepage_all_timeline, viewer = nil)
      @homepage_public_timeline  = TimelineTypes.convert_homepage_all_to_homepage_public(homepage_all_timeline)
      super(homepage_all_timeline, viewer)
    end

    def visible_events
      return @visible_events if defined?(@visible_events)

      event_ids = homepage_private_ids + homepage_public_ids
      sorted_event_ids = event_ids.uniq.sort.reverse.first(::Stratocaster::DEFAULT_INDEX_SIZE)

      unfiltered_events = stratocaster_response { GitHub.stratocaster.ids_to_events(sorted_event_ids) }.items
      StratocasterEventPrefiller.new(unfiltered_events).preload([:senders, :repos])

      filtered_events = filtered_events(unfiltered_events, filters: filters)
      @visible_events = filtered_events
    end

    def preload_events
      # When a timeline is instantiated, #preload_events is called. Preloading
      # generates a stratocaster_response and, normally, grabs all the
      # relevent events. The stratocaster_response is used to hydrate the
      # #unavailable? method in a Timeline. In this case we don't want
      # to instantiate all the Stratocaster::Events because its causing
      # timeouts on the dashboard. Instead, we'll generate the
      # stratocaster_response by fetching just the IDs so that we can
      # check Stratocaster's availability, but not have to instantiate
      # all the events at once.
      #
      timeline_type = TimelineTypes.type_for(timeline)
      GitHub.dogstats.distribution_time("stratocaster.preload_events", tags: ["timeline_type:#{timeline_type}"]) do
        sorted_event_ids
      end
    end

    private

    def sorted_event_ids
      @sorted_event_ids ||= (homepage_private_ids + homepage_public_ids).uniq.sort.reverse.first(::Stratocaster::DEFAULT_INDEX_SIZE)
    end

    def homepage_private_ids
      @homepage_private_ids ||= stratocaster_response { GitHub.stratocaster.ids(homepage_private_timeline) }.items
    end

    def homepage_public_ids
      @homepage_public_ids ||= stratocaster_response { GitHub.stratocaster.ids(homepage_public_timeline) }.items
    end

    def homepage_private_timeline
      timeline
    end

    def filters
      if GitHub.enterprise?
        basic_filters
      else
        filters = basic_filters
        filters.delete(Filters::LabeledEventsFilter)
        filters.delete(Filters::FollowEventsFilter)
        filters.delete(Filters::SponsorEventsFilter)
        filters << Filters::WorkflowEventsFilter
        filters << Filters::DeletedReposFilter
        filters << Filters::DeletedActorsFilter
        filters
      end
    end
  end
end
