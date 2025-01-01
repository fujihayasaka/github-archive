# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class ReleaseComponent < ApplicationComponent
      include GitHub::Memoizer
      include FeedCards::ViewComponentMethods

      HEADING_ICON = { name: :"feed-tag", color: :success }.freeze
      MAX_AVATARS = 6

      # This filter is used in Conduit::Web::Feed to call the batch method `short_description_info`.
      # We must call the batch method with the same params we call the method in this component for preloading to work.
      SHORT_DESCRIPTION_IMG_FILTER = { preview_img_filter: { min_width: 300, max_height: 240 } }.freeze

      private

      def render?
        release.present?
      end

      def heading_icon
        HEADING_ICON
      end

      def render_contributors?
        release.mentions.present?
      end

      def target_user
        if current_user_follows_actor?
          actor
        else
          repository.owner
        end
      end

      memoize def sponsoring?
        target_user.sponsored_by_viewer?(current_user)
      end

      memoize def release
        item.subject
      end

      memoize def repository
        release.repository
      end

      memoize def discussion
        release.discussion
      end

      def release_preview_image
        short_description_info[:preview_img_path]
      end

      def short_description_html
        short_description_info[:html]
      end

      memoize def short_description_info
        release.short_description_info(SHORT_DESCRIPTION_IMG_FILTER)
      end

      def hydro_data(click_target:)
        helpers.feed_clicks_hydro_attrs(click_target: click_target, feed_item: item)
      end

      memoize def current_user_follows_actor?
        # It's expected that this `followed_by` is preloaded
        # by the object rendering the feed (e.g., Conduit::Web::Feed)
        actor.followed_by?(current_user)
      end

      def reaction_count_by_content
        (feed&.reaction_count_by_content_by_release_id || {}).fetch(item.subject_id, {})
      end

      def viewer_reaction_contents
        (feed&.viewer_reaction_contents_by_release_id || {}).fetch(item.subject_id, [])
      end
    end
  end
end
