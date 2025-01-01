# typed: true
# frozen_string_literal: true

module Conduit
  class Timeline
    attr_reader :timeline, :viewer, :feed, :entity_id

    DEFAULT_PER_PAGE = 30
    SUPPORTED_TIMELINES = %w[public org actor user].freeze

    def self.for(timeline_name, viewer)
      unless timeline_supported?(timeline_name)
        raise ArgumentError, "Timeline not supported: #{timeline_name}"
      end

      Conduit::Timeline.new(timeline_name, viewer)
    end

    def self.timeline_supported?(name)
      key = name.split(":").first
      SUPPORTED_TIMELINES.include?(key)
    end

    def initialize(timeline_name, viewer = nil)
      @timeline, id = timeline_name.split(":", 2)
      @entity_id = id&.to_i
      @viewer = viewer
    end

    # This method provides compatibility with Stratocaster::Timeline interface.
    # Returns false since Conduit timelines are typically available.
    def unavailable?
      false
    end

    def events(page: 1, per_page: DEFAULT_PER_PAGE)
      if timeline == "org"
        get_org_timeline_events(page: page, per_page: per_page)
      elsif timeline == "user"
        get_user_timeline_events(page: page, per_page: per_page)
      elsif timeline == "actor"
        get_user_profile_timeline_events(page: page, per_page: per_page)
      else
        get_public_timeline_events(page: page, per_page: per_page)
      end
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
      log_error_and_return_empty_timeline("public")
    end

    def get_org_timeline_events(page:, per_page:)
      events = T.let(nil, T.untyped)
      GitHub.dogstats.distribution_time("conduit.timeline.response_time", tags: ["timeline:org", "success:true"]) do
        twirp_items = GitHub::conduit_client.get_org_feed(viewer: viewer, org_id: entity_id)[:items]
        events = conduit_feed_items(twirp_items, page: page, per_page: per_page)
        GitHub.dogstats.increment("conduit.timeline", tags: ["timeline:org", "success:true"])
      end
      events

    rescue Conduit::Client::Internal
      log_error_and_return_empty_timeline("org")
    end

    def get_user_timeline_events(page:, per_page:)
      user = User.find_by(id: entity_id)
      return [] if user.nil?

      events = T.let(nil, T.untyped)
      GitHub.dogstats.distribution_time("conduit.timeline.response_time", tags: ["timeline:user", "success:true"]) do
        repository_subscriptions = RepositorySubscriptions.for_user(user)
        filter_groups = build_filter_groups(user)
        event_types = build_event_types(filter_groups, user)
        twirp_items = fetch_user_feed_items(
          user:,
          repository_subscriptions:,
          filter_groups:,
          event_types:
        )

        events = conduit_feed_items(twirp_items, page: page, per_page: per_page)
        GitHub.dogstats.increment("conduit.timeline", tags: ["timeline:user", "success:true"])
      end

      events
    rescue Conduit::Client::Internal
      log_error_and_return_empty_timeline("user")
    end

    def get_user_profile_timeline_events(page:, per_page:)
      events = T.let(nil, T.untyped)

      GitHub.dogstats.distribution_time("conduit.timeline.response_time", tags: ["timeline:user_public", "success:true"]) do
        profile_user = User.find_by(id: entity_id)
        twirp_items = GitHub::conduit_client.get_user_events(
          viewer: viewer,
          user: profile_user,
          public_only: true
        )[:items]
        events = conduit_feed_items(twirp_items, page: page, per_page: per_page)
        GitHub.dogstats.increment("conduit.timeline", tags: ["timeline:user_public", "success:true"])
      end
      events

    rescue Conduit::Client::Internal
      log_error_and_return_empty_timeline("user_public")
    end

    def build_filter_groups(user)
      filter_settings = ForYouFeedFilterSettings.where(user_id: user.id).first
      values = filter_settings&.values
      Conduit::FeedFilter.new(values, viewer: user).without_groups(%w[Announcements Sponsors Recommendations])
    end

    def build_event_types(filter_groups, user)
      Conduit::FeedFilter.new(filter_groups, viewer: user).event_types
    end

    def fetch_user_feed_items(user:, repository_subscriptions:, filter_groups:, event_types:)
      GitHub::conduit_client.get_for_you_feed(
        user:,
        variants: {},
        disable_cache: disable_conduit_cache?,
        include_starred_relationships: filter_groups["StarredRelationships"],
        repository_subscriptions:,
        event_types:
      )[:items]
    end

    def conduit_feed_items(twirp_items, page:, per_page:)
      @feed = ::Conduit::Atom::Feed.new(
        viewer,
        viewer:,
        twirp_items:,
        per_page:,
        page:,
      ).build
      feed.items
    end

    def disable_conduit_cache?
      FeatureFlag.vexi.enabled?(:feeds_conduit_cache_opt_out, viewer, default: false)
    end

    def log_error_and_return_empty_timeline(timeline_type)
      GitHub.dogstats.increment("conduit.timeline", tags: ["timeline:#{timeline_type}", "success:false"])
      []
    end
  end
end
