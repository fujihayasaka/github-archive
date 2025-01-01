# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class UserBaseComponent < BaseComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      private

      memoize def user
        display_subject
      end

      def user_name
        user.profile_name || user.display_login
      end

      memoize def user_repo_count
        user.public_repository_count
      end

      memoize def user_follower_count
        user.followers_count(viewer: current_user)
      end

      memoize def description
        if sponsored_action?
          user.sponsors_bio_html
        else
          user.profile_bio_html
        end
      end

      memoize def sponsoring?
        user.sponsored_by_viewer?(current_user)
      end

      def render_description?
        description.present?
      end

      def render_counts?
        return false if sponsored_action? && !subject_is_current_user?
        render_repo_count? || render_follower_count?
      end

      def render_repo_count?
        user_repo_count > 0
      end

      def render_follower_count?
        user_follower_count > 0
      end

      def render_sponsor_button?
        sponsored_action? && user.sponsorable?
      end

      def followed_action?
        item.followed_action?
      end

      def sponsored_action?
        item.sponsored_action?
      end

      def subject_is_current_user?
        return false unless logged_in?
        item.subject.id == current_user.id
      end

      memoize def sponsors_listing
        user.sponsors_listing
      end

      memoize def sponsors_goal
        sponsors_listing.active_goal
      end

      def hydro_data(click_target:)
        helpers.feed_clicks_hydro_attrs(click_target: click_target, feed_item: item)
      end
    end
  end
end
