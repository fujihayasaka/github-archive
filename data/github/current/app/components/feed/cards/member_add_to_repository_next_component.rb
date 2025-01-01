# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class MemberAddToRepositoryNextComponent < ApplicationComponent
      include FeedCards::RepositoryViewComponentMethods
      include GitHub::Memoizer

      HEADING_ICON = { name: :"feed-add-user", exported: true }.freeze

      private

      def member
        item.subject.member
      end

      def render?
        item.render? && member.present?
      end

      def heading_icon
        HEADING_ICON
      end

      memoize def user
        display_subject
      end

      def user_name
        member.profile_name || member.display_login
      end

      memoize def user_repo_count
        member.public_repository_count
      end

      memoize def user_follower_count
        member.followers_count(viewer: current_user)
      end

      memoize def description
        member.profile_bio_html
      end

      memoize def sponsoring?
        member.sponsored_by_viewer?(current_user)
      end

      def render_description?
        description.present?
      end

      def render_counts?
        render_repo_count? || render_follower_count?
      end

      def render_repo_count?
        user_repo_count > 0
      end

      def render_follower_count?
        user_follower_count > 0
      end

      def render_sponsor_button?
        false
      end

      def subject_is_current_user?
        return false unless logged_in?
        item.subject.id == current_user.id
      end

      memoize def sponsors_listing
        member.sponsors_listing
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
