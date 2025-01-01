# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class BaseComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      include GitHub::Memoizer

      def initialize(
        item:,
        viewer: nil,
        feed: nil,
        show_star_repo_buttons: false,
        stats_timer_method: nil,
        stats: nil
      )
        @item = item
        @viewer = viewer
        @feed = feed
        @show_star_repo_buttons = show_star_repo_buttons
        @stats_timer_method = stats_timer_method
        @stats = stats
      end

      # override in subclasses if needed
      def heading_icon
        nil
      end

      private

      attr_accessor :idx
      attr_reader :item, :feed, :viewer, :show_star_repo_buttons, :stats

      delegate(
        :action_string,
        :actor,
        :analytics_attributes,
        :announcement?,
        :contains_viewer?,
        :display_subject,
        :feed_post,
        :repository,
        :subject,
        :subject_id,
        :user_list,
        to: :item,
      )

      alias_method :action, :action_string

      def stats_timer
        if @stats_timer_method
          @stats_timer_method.call(stats, tags: ["item_key:#{item.item_key}"]) { yield }
        else
          yield
        end
      end
    end
  end
end
