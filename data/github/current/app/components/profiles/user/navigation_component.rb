# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class NavigationComponent < BaseNavigationComponent
      private

      delegate(
        :open_public_projects_count,
        :packages_count,
        :repository_count,
        :profile_user,
        :sponsoring_count,
        :stars_count,
        :user_is_viewer?,
        :active_and_inactive_sponsoring_count,
        to: :profile_layout_data,
      )

      memoize def show_sponsoring_tab?
        return false unless GitHub.sponsors_enabled?

        active_and_inactive_sponsoring_count.positive?
      end

      memoize def show_packages_tab?
        PackageRegistryHelper.show_packages? && PackageRegistryHelper.allow_access_to_actor?(profile_user, current_user)
      end

      def show_activity_tab?
        profile_activity_enabled_for_viewer?
      end

      def user_project_path
        user_path(profile_user, params: { tab: :projects })
      end

      def projects_icon
        "table"
      end

      def activity_icon
        "comment"
      end

      memoize def profile_activity_enabled_for_viewer?
        return false unless GitHub.conduit_feed_enabled?
        return false unless GitHub.flipper[:feed_posts].enabled?(current_user)

        profile_feed_is_public = profile_user.settings.get(:user_profile_feed_visible)
        user_is_viewer? || profile_feed_is_public
      end

      def user_packages_path
        @user_packages_path ||= user_path(profile_user, params: { tab: :packages })
      end

      memoize def user_activity_path
        user_path(profile_user, params: { tab: :activity })
      end

      def user_stars_path
        @user_stars_path ||= user_path(profile_user, params: { tab: :stars })
      end

      def user_sponsoring_path
        @user_sponsoring_path ||= user_path(profile_user, params: { tab: :sponsoring })
      end
    end
  end
end
