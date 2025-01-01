# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class DiscussionComponent < ApplicationComponent
      include GitHub::Memoizer
      include FeedCards::ViewComponentMethods

      HEADING_ICON = { name: :"feed-discussion", color: :done }.freeze
      GRADIENT_BORDERS = [
        "93.23deg, #F778BA 2.35%, #79C0FF 76.99%",
        "92.21deg, #79C0FF 0%, #D2A8FF 57.57%",
        "92.05deg, #D2A8FF 12.09%, #F778BA 42.58%, #FF7B72 84.96%",
        "267.91deg, #E1CD41 9.35%, #F97583 96.48%, #FF7B72 96.48%",
        "92.7deg, #56D364 -1.37%, #79C0FF 78.71%"
      ].freeze

      private

      def render?
        discussion.present? && item.detected_language_english?
      end

      def heading_icon
        HEADING_ICON
      end

      def discussion
        subject
      end

      memoize def repository
        discussion.repository
      end

      def repository_discussions_path
        discussions_path(discussion.repository_owner_login, repository)
      end

      memoize def discussion_body_html
        discussion.body_html
      end

      memoize def max_discussion_body_length
        announcement? ? 150 : 360
      end

      memoize def truncated_discussion_body_html
        discussion_body_truncator.to_html(wrap: false)
      end

      memoize def discussion_body_truncator
        HTMLTruncator.new(discussion_body_html, max_discussion_body_length, keep_svg_elements: true, strip_block_elements: false, preview_img_filter: { min_width: 300, max_height: 240 })
      end

      def discussion_body_truncated?
        discussion_body_truncator.remaining.content.present?
      end

      def discussion_preview_image
        if item.universe_announcement?
          item.async_preview_image_url(viewer: @viewer).sync
        elsif announcement?
          nil
        else
          discussion_body_truncator.preview_img_path
        end
      end

      def discussion_category_path
        category_discussions_path(
          user_id: discussion.repository_owner_login,
          repository: discussion.repository,
          category_slug: discussion.category.slug
        )
      end

      def target_user
        if current_user_follows_actor?
          actor
        else
          repository.owner
        end
      end

      memoize def action
        if current_user_follows_actor?
          "created #{action_string}"
        else
          "has #{action_string}"
        end
      end

      def discussion_link_data(click_target:)
        helpers.feed_discussion_link_data(
          repo: repository,
          number: discussion.number,
          click_target: click_target,
          feed_item: item
        )
      end

      def discussion_footer_comments_link_text
        if discussion_has_comments?
          helpers.pluralize(discussion.comment_count, "comment")
        else
          "Comment"
        end
      end

      def announcement_footer_comments_link_text
        if discussion_has_comments?
          discussion.comment_count
        else
          ""
        end
      end

      memoize def current_user_follows_actor?
        # It's expected that this `followed_by` is preloaded
        # by the object rendering the feed (e.g., Conduit::Web::Feed)
        actor.followed_by?(current_user)
      end

      memoize def discussion_has_comments?
        discussion.comment_count > 0
      end

      def current_user
        @viewer || helpers.current_user
      end

      def hydro_data(click_target:)
        helpers.feed_clicks_hydro_attrs(click_target: click_target, feed_item: item)
      end

      def reaction_form_context
        {}
      end

      def reaction_count_by_content
        (feed&.reaction_count_by_content_by_discussion_id || {}).fetch(item.subject_id, {})
      end

      def viewer_reaction_contents
        (feed&.viewer_reaction_contents_by_discussion_id || {}).fetch(item.subject_id, [])
      end

      def gradient
        GRADIENT_BORDERS[announcement_position % GRADIENT_BORDERS.length]
      end

      def announcement_position
        item.sub_idx || 0
      end
    end
  end
end
