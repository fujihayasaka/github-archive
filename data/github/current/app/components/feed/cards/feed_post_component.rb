# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class FeedPostComponent < ApplicationComponent
      include GitHub::Memoizer
      include FeedCards::ViewComponentMethods

      private

      memoize def body_html
        feed_post.body_html
      end

      def post_id
        feed_post.id
      end

      def comments
        feed_post.comments
      end

      def action
        "shared #{action_string}"
      end

      def timestamp
        item.created_at
      end

      def hydro_data(click_target:)
        helpers.feed_clicks_hydro_attrs(click_target: click_target, feed_item: item)
      end

      memoize def reaction_count_by_content
        return {} unless feed
        feed
          .reaction_count_by_content_by_feed_post_id
          .fetch(item.subject_id, {})
      end

      memoize def user_reactions
        feed_post.prelude_user_logins_by_reaction
      end

      memoize def viewer_reaction_contents
        return [] unless feed
        feed
          .viewer_reaction_contents_by_feed_post_id
          .fetch(item.subject_id, [])
      end
    end
  end
end
