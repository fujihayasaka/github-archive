# typed: true
# frozen_string_literal: true

class DiscussionsController
  class ShowStats
    MEDIAN_COMMENTS_PER_DISCUSSION = 8

    def initialize(discussion:, viewer:)
      @discussion = discussion
      @viewer = viewer
      @deferred_distributions = {}
      @deferred_render_distributions = []
    end

    # This is meant to be used in an around_action.
    def instrument_controller_action
      start_time = GitHub::Dogstats.monotonic_time
      Site::GlobalNoticeComponent.check_for_notices_elapsed = 0
      response_successful = yield

      return unless discussion && response_successful

      if global_notice_elapsed = Site::GlobalNoticeComponent.check_for_notices_elapsed
        @deferred_distributions[:global_notice] = global_notice_elapsed
      end

      elapsed = GitHub::Dogstats.duration(start_time)

      GitHub.dogstats.distribution(
        "discussions.show.dist.time",
        elapsed,
        tags: show_stats_tags,
      )

      @deferred_distributions.each do |name, value|
        GitHub.dogstats.distribution(
          "discussions.show.#{name}.dist.time",
          value,
          tags: show_stats_tags
        )
      end

      @deferred_render_distributions.each do |render|
        GitHub.dogstats.distribution(
          "discussions.show.render.dist.time",
          render.fetch(:elapsed),
          tags: show_stats_tags + ["partial:#{render.fetch(:name)}"]
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

    def record_render(renderable_name)
      start_time = GitHub::Dogstats.monotonic_time
      result = yield
      elapsed = GitHub::Dogstats.duration(start_time)
      @deferred_render_distributions << {
        name: renderable_name,
        elapsed: elapsed,
      }
      result
    end

    private

    attr_reader :discussion, :viewer

    def show_stats_tags
      return @_show_stats_tags if defined?(@_show_stats_tags)

      @_show_stats_tags = []
      if size = discussion_size
        @_show_stats_tags << "discussion_size:#{size}"
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

    def discussion_size
      case discussion.comment_count
      when 0 then :empty
      when 1 then :minimal
      when (MEDIAN_COMMENTS_PER_DISCUSSION - 2)..(MEDIAN_COMMENTS_PER_DISCUSSION + 2)
        :median
      when (100..)
        :long
      else
        nil
      end
    end

    def preload_permissions?
      @preload_permissions
    end
  end
end
