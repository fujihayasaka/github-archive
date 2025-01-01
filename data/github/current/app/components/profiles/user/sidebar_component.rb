# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class SidebarComponent < ApplicationComponent
      extend T::Helpers

      sig { params(profile_layout_data: T.untyped, gists_profile: T.untyped).void }
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
        :follow_button,
        :sponsors_button_hydro_attributes,
        :profile_avatar_using,
        :profile_click_tracking_attrs,
        :user_pronouns_enabled?,
        to: :helpers,
      )

      delegate(
        :discussion_answered_count,
        :followers_count,
        :following_count,
        :global_advisory_credit_count,
        :has_pro_plan_badge?,
        :bounty_hunter?,
        :campus_expert?,
        :github_star?,
        :show_sponsor_button?,
        :show_follow_button?,
        :sponsorable?,
        :sponsored_by_viewer?,
        :stars_count,
        :login_name,
        :primary_avatar_url,
        :profile_name,
        :profile_user,
        :site_admin?,
        :user_is_viewer?,
        :viewer_blocking_profile_user?,
        :ignored_user_record,
        :hide_from_viewer?,
        to: :profile_layout_data,
      )

      def gists_profile?
        @gists_profile
      end
    end
  end
end
