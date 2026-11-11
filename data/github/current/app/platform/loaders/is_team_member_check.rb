# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class IsTeamMemberCheck < Platform::Loader
      def self.load(user_id, team_id, immediate_only: false, with_business_teams: false)
        self.for(user_id, immediate_only, with_business_teams).load(team_id)
      end

      def initialize(user_id, immediate_only, with_business_teams)
        @user_id = user_id
        @immediate_only = immediate_only
        @with_business_teams = with_business_teams
      end

      def fetch(team_ids)
        accessible_team_scope = ::Ability
                                         .where(actor_id: @user_id,
                                                actor_type: "User",
                                                subject_id: team_ids,
                                                subject_type: @with_business_teams ? %w[Team BusinessTeam] : "Team")
        accessible_team_scope = if @immediate_only
          accessible_team_scope.where(priority: ::Ability.priorities[:direct])
        else
          accessible_team_scope.where("priority <= ?", ::Ability.priorities[:direct])
        end

        accessible_team_scope.pluck(:subject_id).each_with_object(Hash.new(false)) do |team_id, result|
          result[team_id] = true
        end
      end
    end
  end
end
