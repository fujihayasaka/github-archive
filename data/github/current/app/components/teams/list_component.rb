# typed: true
# frozen_string_literal: true

module Teams
  class ListComponent < ApplicationComponent
    VISIBLE_MEMBER_RANGE = 5

    def initialize(teams:)
      @teams = teams
      @member_ids_for_teams = teams.present? ? Team.member_ids_indexed_by_team_ids(teams.map(&:id)) : {}
    end

    private

    def render?
      @teams.present?
    end

    def visible_member_range
      VISIBLE_MEMBER_RANGE
    end

    def members_count(team)
      @member_ids_for_teams[team.id].size
    end

    def members(team_id)
      visible_members_by_team[team_id]
    end

    memoize def visible_members_by_team
      # Limit IDs first
      visible_member_ids_for_teams = @member_ids_for_teams.transform_values do |member_ids|
        member_ids.first(visible_member_range)
      end

      all_user_ids = visible_member_ids_for_teams.values.flatten.uniq
      users_by_id = User.where(id: all_user_ids).index_by(&:id)

      # Map user id to loaded user record
      visible_member_ids_for_teams.transform_values do |member_ids|
        member_ids.filter_map do |user_id|
          users_by_id[user_id]
        end
      end
    end
  end
end
