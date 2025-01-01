# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class SidebarComponent < BaseSidebarComponent
      private

      delegate(
        :follow_button,
        :sponsors_button_hydro_attributes,
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
        to: :profile_layout_data,
      )

      def gists_profile?
        @gists_profile
      end
    end
  end
end
