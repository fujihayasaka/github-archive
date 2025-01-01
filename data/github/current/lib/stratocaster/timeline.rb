# typed: false
# frozen_string_literal: true

module Stratocaster
  # A simplified interface to Stratocaster::Service to fetch events
  # in a given timeline.
  class Timeline
    include Filters

    attr_reader :timeline
    attr_reader :viewer

    # Creates the particular instance of Timeline or any of its sublcasses
    # that defines the retrieval strategy for the given key.
    #
    def self.for(key, viewer, options = {})
      if TimelineTypes.org_all_timeline?(key)
        timeline = Stratocaster::OrgAllTimeline.new(key, viewer)
        timeline_type = "org_all"
      elsif TimelineTypes.user_received_events_timeline?(key)
        timeline = Stratocaster::UserReceivedEventsTimeline.new(key, viewer)
        timeline_type = "received_events"
      elsif TimelineTypes.homepage_all_timeline?(key)
        timeline = Stratocaster::HomepageAllTimeline.new(key, viewer)
        timeline_type = "homepage_all"
      else
        timeline = Stratocaster::Timeline.new(key, viewer)
        timeline_type = "rest"
      end

      GitHub.dogstats.increment("stratocaster.timeline_for", tags: ["timeline_type:#{timeline_type}"])

      timeline
    end

    # Create an instance of the filter.
    #
    # key - String key of the index-entry that holds the events that make up
    # this timeline.
    # viewer   - User instance viewing the timeline
    def initialize(key, viewer = nil)
      @timeline = key.to_s
      @viewer   = viewer
      preload_events
    end

    # Fetch the events for a page in the timeline.
    #
    # page - Integer page number.
    #
    # Returns an Array of Stratocaster::Events.
    def events(page: 1, per_page: Stratocaster::DEFAULT_PAGE_SIZE)
      visible_events.paginate(page: page, per_page: per_page)
    end

    # Preload the events.
    #
    # Return an Array of Stratocaster::Events.
    def preload_events
      timeline_type = TimelineTypes.type_for(timeline)
      GitHub.dogstats.distribution_time("stratocaster.preload_events", tags: ["timeline_type:#{timeline_type}"]) do
        visible_events
      end
    end

    # Indicates if the timeline contains only public events.
    #
    # timeline - String name of the timeline.
    #
    # Returns a Boolean.
    def public?
      timeline.to_s.ends_with?("public")
    end

    # Public: If we had trouble retrieving the events from Stratocaster, we should mark the
    # response as unavailable.
    #
    # Returns true or false.
    def unavailable?
      @stratocaster_response.unavailable?
    end

    # A unique string hash for a given timeline and array of events,
    # useful for ETags.
    #
    # timeline - String timeline key.
    # events   - Array of Stratocaster::Event instances.
    #
    # Returns a String.
    def self.fingerprint(timeline, events)
      ids = events.map(&:id)
      Digest::SHA256.hexdigest(timeline.to_s + ids.join(":"))
    end

    # Public: Returns how many events are in this timeline.
    def event_count
      event_ids.size
    end

    private

    def stratocaster_response(&block)
      @stratocaster_response = Stratocaster::Response.new do
        block.call
      end
    end

    # Fetch all pages of the timeline before applying filtering
    def all_events
      return @all_events if defined?(@all_events)
      @all_events = stratocaster_response do
        GitHub.
          stratocaster.
          events(timeline)
      end.items

      StratocasterEventPrefiller.new(@all_events).preload(:senders)
      @all_events
    end

    def event_ids
      stratocaster_response { GitHub.stratocaster.ids(timeline) }.items
    end

    # Filter all events in the timeline based on the viewer's
    # timeline filter, or all events for public feeds.
    def visible_events
      return @visible_events if defined?(@visible_events)

      @visible_events = if viewer_can_view_entire_timeline?(viewer)
        filtered_events(all_events, filters: [
          Filters::LabeledEventsFilter,
          Filters::FollowEventsFilter,
          Filters::SponsorEventsFilter,
          Filters::ReleaseEventsFilter,
          Filters::PrivateProfilesFilter,
          Filters::RetentionFilter,
        ])
      else
        filtered_events(all_events, filters: basic_filters)
      end
    end

    # Private: Filters the given events with this user's applicable timeline
    # filters. Applies base filters first, then permission filters,
    # then visibility filters.
    def filtered_events(all_events, filters:)
      return all_events unless filters && filters.any?
      events = all_events.dup
      filters.each do |filter|
        events = filter.apply(events, viewer)
      end
      events
    end

    # Private: An array of basic filters to apply to filter
    # the timeline for the current viewer.
    #
    # Returns an array of filters that respond to #apply.
    def basic_filters
      filters = [
        Filters::IgnoredUsersFilter,
        Filters::SpamFilter,
        Filters::ConditionalAccessFilter,
        Filters::LabeledEventsFilter,
        Filters::FollowEventsFilter,
        Filters::OrgFollowEventsFilter,
        Filters::PrivateProfilesFilter,
        Filters::SponsorEventsFilter,
        Filters::ReleaseEventsFilter,
      ]
      filters << Filters::OauthApplicationFilter if viewer.using_oauth_application?
      filters << Filters::AppsFilter if viewer.can_have_granular_permissions?
      filters << Filters::RetentionFilter if viewer.feature_enabled?(:stratocaster_retention_filter)
      filters
    end

    # Private: can the given viewer view the entire timeline
    # without filtering?
    #
    # Returns true or false.
    def viewer_can_view_entire_timeline?(viewer)
      viewer.nil?
    end
  end
end
