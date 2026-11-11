# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class UserTeams < Platform::Loader
      def self.load(user, with_ancestors:, with_business_teams: false)
        return ::Promise.resolve([]) unless user.present?

        promise = self.for(with_business_teams:).load(user.id)

        return promise unless with_ancestors

        promise.then do |team_ids|
          # load the Team records because we need the `tree_path` for descendants
          scope = with_business_teams ? ::Team.with_business_teams : ::Team
          Loaders::ActiveRecord.load_all(scope, team_ids).then do |teams|
            nested_team_ids = teams.flat_map do |team|
              # Fetch ancestors while being robust to non-existent teams.
              # See https://github.com/github/github/issues/92478.
              team&.id_and_ancestor_ids || []
            end
            nested_team_ids.compact.uniq.sort
          end
        end
      end

      def initialize(with_business_teams: false)
        @with_business_teams = with_business_teams
      end

      # Internal: fetch the Team IDs for the list of User IDs.
      #
      # Returns a Hash{user_id Integer => Array[team_id Integer...]}.
      def fetch(user_ids)
        results = Hash.new { |h, k| h[k] = [] }

        subject_type = if @with_business_teams
          %w{Team BusinessTeam}
        else
          "Team"
        end
        ::Ability.distinct.where(
          actor_type: "User",
          actor_id: user_ids,
          subject_type: subject_type,
          priority: ::Ability.priorities[:direct],
        ).pluck(:actor_id, :subject_id).each do |actor_id, subject_id|
          results[actor_id] << subject_id
        end

        results
      end
    end
  end
end
