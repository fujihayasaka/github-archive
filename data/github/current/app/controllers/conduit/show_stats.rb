# typed: true
# frozen_string_literal: true

module Conduit
  class ShowStats
    def initialize(feed:, viewer:)
      @feed = feed
      @viewer = viewer
      @deferred_distributions = {}
      @deferred_render_distributions = []
    end

    # This is meant to be used in an around_action.
    def instrument_controller_action
      start_time = GitHub::Dogstats.monotonic_time
      Site::GlobalNoticeComponent.check_for_notices_elapsed = 0
      response = yield

      return unless feed && response.successful?

      if global_notice_elapsed = Site::GlobalNoticeComponent.check_for_notices_elapsed
        @deferred_distributions[:global_notice] = global_notice_elapsed
      end

      elapsed = GitHub::Dogstats.duration(start_time) # in ms

      GitHub.dogstats.distribution(
        "feeds.show.dist.time",
        elapsed,
        tags: show_stats_tags,
      )

      @deferred_distributions.each do |name, value|
        GitHub.dogstats.distribution(
          "feeds.show.#{name}.dist.time",
          value, # in ms
          tags: show_stats_tags
        )
      end

      @deferred_render_distributions.each do |render|
        GitHub.dogstats.distribution(
          "feeds.show.render.dist.time",
          render.fetch(:elapsed), # in ms
          tags: show_stats_tags + ["rendered:#{render.fetch(:name)}"] + (render.dig(:tags) || [])
        )
      end
    end

    def record_distribution(name)
      start_time = GitHub::Dogstats.monotonic_time
      result = yield
      elapsed = GitHub::Dogstats.duration(start_time)
      @deferred_distributions[name] = elapsed
      result
    end

    def record_render(renderable_name, **kwargs)
      start_time = GitHub::Dogstats.monotonic_time
      result = yield
      elapsed = GitHub::Dogstats.duration(start_time)
      @deferred_render_distributions << {
        name: renderable_name,
        elapsed: elapsed,
        **kwargs
      }
      result
    end

    private

    attr_reader :feed, :viewer

    def show_stats_tags
      return @_show_stats_tags if defined?(@_show_stats_tags)

      @_show_stats_tags = []
      if length = feed_item_length
        @_show_stats_tags << "feed_length:#{length}"
      end

      viewer_tag_value =
        if viewer&.site_admin?
          "site_admin"
        elsif viewer
          "user"
        else
          "anonymous"
        end

      @_show_stats_tags << "viewer:#{viewer_tag_value}"
      @_show_stats_tags
    end

    def feed_item_length
      feed.items.length
    end

    def preload_permissions?
      @preload_permissions
    end
  end
end
