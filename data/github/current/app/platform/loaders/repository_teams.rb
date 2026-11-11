# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryTeams < Platform::Loader
      def self.load(repository, immediate_only:, include_all_repo_roles: false, with_business_teams: false, optimized: false, reviewer_teams_all_repo_role_enabled: false)
        return ::Promise.resolve([]) unless repository.present?

        promise = self.for(with_business_teams: with_business_teams).load(repository.id)

        if include_all_repo_roles && reviewer_teams_all_repo_role_enabled
          direct_all_repo_grants = repository.all_repo_role_grants(:read)
          promise = promise.then do |team_ids|
            team_ids += T.must(direct_all_repo_grants["Team"]) if direct_all_repo_grants.key?("Team")
            if with_business_teams
              team_ids += T.must(direct_all_repo_grants["BusinessTeam"]) if direct_all_repo_grants.key?("BusinessTeam")
            end
            team_ids.uniq!
            team_ids
          end
        end

        return promise if immediate_only

        promise.then do |team_ids|
          # load the Team records because we need the `tree_path` for descendants
          scope = with_business_teams ? ::Team.with_business_teams : ::Team
          Loaders::ActiveRecord.load_all(scope, team_ids).then do |teams|
            teams.compact! # in case Teams cannot be found by ID
            next [] if teams.empty?

            Loaders::TeamDescendants.load_all(teams, immediate_only: false, optimized:).then do |descendant_ids_by_parent_id|
              descendant_ids_by_parent_id.to_a.flatten.compact.uniq.sort
            end
          end
        end
      end

      def initialize(with_business_teams: false)
        @with_business_teams = with_business_teams
      end

      # Internal: fetch the Team IDs for the list of Repository IDs.
      #
      # Returns a Hash{repository_id Integer => Array[team_id Integer...]}.
      def fetch(repo_ids)
        results = Hash.new { |h, k| h[k] = [] }

        actor_types = @with_business_teams ? %w(Team BusinessTeam) : "Team"
        ::Ability.distinct.where(
          actor_type: actor_types,
          subject_type: "Repository",
          subject_id: repo_ids,
          priority: ::Ability.priorities[:direct],
        ).pluck(:actor_id, :subject_id).each do |actor_id, subject_id|
          results[subject_id] << actor_id
        end

        results
      end
    end
  end
end
