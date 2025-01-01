# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class BaseSidebarComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      # profile_layout_data - a Profiles::User::LayoutData instance
      def initialize(profile_layout_data:, gists_profile: false)
        @profile_layout_data = profile_layout_data
        @gists_profile = gists_profile
      end

      def render?
        !hide_from_viewer?
      end

      private

      attr_reader :profile_layout_data

      delegate(
        :profile_avatar_using,
        :profile_click_tracking_attrs,
        :preview_features?,
        :show_block_button?,
        :user_pronouns_enabled?,
        to: :helpers,
      )

      delegate(
        :hide_from_viewer?,
        :login_name,
        :primary_avatar_url,
        :profile_name,
        :profile_user,
        :site_admin?,
        :user_is_viewer?,
        :viewer_blocking_profile_user?,
        :ignored_user_record,
        to: :profile_layout_data,
      )

      def gists_profile?
        @gists_profile
      end
    end
  end
end
