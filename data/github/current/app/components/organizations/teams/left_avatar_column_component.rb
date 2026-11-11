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

      def team_primary_avatar_url
        team.unique_avatar_url(116)
      end

      def user_on_team?
        team.member?(current_user)
      end

      memoize def show_enterprise_label?
        team.enterprise_team_managed?
      end

      memoize def show_enterprise_label_v2?
        team.business_team?
      end
    end
  end
end
