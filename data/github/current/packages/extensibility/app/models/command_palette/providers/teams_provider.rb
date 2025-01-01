# typed: true
# frozen_string_literal: true

module CommandPalette
  module Providers
    class TeamsProvider < ApplicationProvider
      def self.modes
        [:owner_jump_to, :modeless_owner]
      end

      def search(query)
        return [] unless scope.organization?

        if query.include?(scope.organization.login)
          query = query.gsub(scope.organization.login, "").gsub("/", "")
        end

        teams = scope.organization.team_search_for_user(TeamSearchQuery.new(query), current_user)
        teams = T.unsafe(Team).ranked_for(current_user, scope: teams).limit(100)

        # Order is ascending, so the first teams are the lowest ranked.
        teams.reverse.map.with_index do |team, index|
          Result.jump_to(team, priority: index, context: context)
        end
      end
    end
  end
end
