# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    class SidebarComponent < ApplicationComponent
      include ::CacheHelper
      include ProfilesHelper

      def initialize(profile_layout_data:)
        @profile_layout_data = profile_layout_data
      end

      def render?
        !hide_from_viewer? && !user_or_organization_restricted?
      end

      private

      attr_reader :profile_layout_data

      def top_languages_cache_key
        org_profile_cache_key(
          feature: "top_languages",
          organization: profile_layout_data.profile_organization,
          direct_or_team_member: direct_or_team_member?,
          org_profile_overview: true,
        )
      end

      def most_used_topics_cache_key
        org_profile_cache_key(
          feature: "most_used_topics",
          organization: profile_layout_data.profile_organization,
          direct_or_team_member: direct_or_team_member?,
          org_profile_overview: true,
        )
      end

      memoize def show_report_abuse_link?
        GitHub.user_abuse_mitigation_enabled? && logged_in? && !profile_layout_data.profile_organization.direct_or_team_member?(current_user)
      end

      memoize def show_org_discussions?
        logged_in? && FeatureFlag.vexi.enabled?(:organization_profile_discussions, current_user, default: false)
      end

      memoize def org_discussions_viewable?
        show_org_discussions? &&
        org_discussions_repository.present? &&
        org_discussions_repository.readable_by?(current_user)
      end

      memoize def org_discussions_repository
        profile_organization.discussion_repository&.repository
      end

      memoize def current_user_can_enable_org_discussions?
        show_org_discussions? && profile_organization.adminable_by?(current_user)
      end

      def top_border_class(component)
        top_border = "mb-3 py-3 border-top"
        no_top_border = "mb-3 pb-3"

        return top_border if helpers.show_profile_toggle?(profile_organization)

        if org_discussions_viewable?
          component == Discussions::OverviewDiscussionsComponent ? no_top_border : top_border
        elsif current_user_can_enable_org_discussions?
          component == Discussions::EnableDiscussionsComponent ? no_top_border : top_border
        else
          component == Profiles::Organization::MembersComponent ? no_top_border : top_border
        end
      end

      delegate(
        :profile_avatar_using,
        :profile_click_tracking_attrs,
        to: :helpers,
      )

      delegate(
        :direct_or_team_member?,
        :hide_from_viewer?,
        :primary_avatar_url,
        :profile_name,
        :profile_organization,
        :show_developer_program_member_badge?,
        :show_github_sponsor_recognition?,
        :show_sponsor_button?,
        :site_admin?,
        :sponsorable?,
        :user_or_organization_restricted?,
        to: :profile_layout_data,
      )

    end
  end
end
