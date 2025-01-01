# typed: true
# frozen_string_literal: true

module Conduit
  class Timeline
    attr_reader :timeline, :viewer, :feed

    DEFAULT_PER_PAGE = 30
    SUPPORTED_TIMELINES = %w[public].freeze

    def self.for(timeline_name, viewer)
      unless timeline_supported?(timeline_name)
        raise ArgumentError, "Timeline not supported: #{timeline_name}"
      end

      Conduit::Timeline.new(timeline_name, viewer)
    end

    def self.timeline_supported?(name)
      SUPPORTED_TIMELINES.include?(name)
    end

    def initialize(timeline_name, viewer = nil)
      @timeline = timeline_name.to_s
      @viewer = viewer

      # currently only supporting "public" timeline, but will be expanded
      # to support other timelines in follow-up PRs for planned work
      # https://github.com/github/sunset-squad/issues/85
    end

    def events(page: 1, per_page: DEFAULT_PER_PAGE)
      get_public_timeline_events(page: page, per_page: per_page)
    end

    private

    def get_public_timeline_events(page:, per_page:)
      events = T.let(nil, T.untyped)
      GitHub.dogstats.distribution_time("conduit.timeline.response_time", tags: ["timeline:public", "success:true"]) do
        twirp_items = GitHub::conduit_client.get_public_events(viewer:)[:items]
        events = conduit_feed_items(twirp_items, page: page, per_page: per_page)
        GitHub.dogstats.increment("conduit.timeline", tags: ["timeline:public", "success:true"])
      end
      events

    rescue Conduit::Client::Internal
      GitHub.dogstats.increment("conduit.timeline", tags: ["timeline:public", "success:false"])
      []
    end

    def conduit_feed_items(twirp_items, page:, per_page:)
      @feed = ::Conduit::Web::Feed.new(
        viewer,
        viewer:,
        twirp_items:,
        per_page:,
        page:,
      ).build

      feed.items
    end
  end
end
