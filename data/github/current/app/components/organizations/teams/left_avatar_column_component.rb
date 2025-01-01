# typed: true
# frozen_string_literal: true

module Organizations
  module Teams
    class LeftAvatarColumnComponent < ApplicationComponent
      include GitHub::Memoizer
      include AvatarHelper

      # team - a Team whose name and avatar should be shown
      def initialize(team:)
        @team = team
      end

      private

      attr_reader :team

      def render?
        team.present?
      end

      memoize def viewer_can_administer_team?
        team.adminable_by?(current_user)
      end

      memoize def viewer_can_see_archive_link?
        team.post_archive_readable_by?(current_user)
      end

      memoize def archived_team_posts?
        team.get_team_posts_scope(current_user).count > 0
      end

      def team_primary_avatar_url
        team.primary_avatar_url(116)
      end

      def user_on_team?
        team.member?(current_user)
      end

      memoize def show_enterprise_label?
        team.enterprise_team_managed?
      end

      memoize def show_enterprise_label_v2?
        team.business_team? && team.business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
      end
    end
  end
end
