# typed: true
# frozen_string_literal: true

module CommandPalette
  module Results
    class TeamResult < Result
      def self.type
        Team
      end

      def self.create(team, priority, context, group = nil)
        new(
          priority: priority,
          title: team.name_with_owner,
          icon: Icons::Avatar.new(url: team.primary_avatar_url(56), alt: team.name_with_owner),
          action: Actions::JumpToTeamAction.new(path: team_path(team.owner, team)),
          group: group || :teams,
          object: team
        )
      end
    end
  end
end
