# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryTeams < Platform::Loader
      def self.load(repository, immediate_only:)
        return ::Promise.resolve([]) unless repository.present?

        promise = self.for.load(repository.id)

        return promise if immediate_only

        promise.then do |team_ids|
          # load the Team records because we need the `tree_path` for descendants
          Loaders::ActiveRecord.load_all(::Team, team_ids).then do |teams|
            teams.compact! # in case Teams cannot be found by ID
            next [] if teams.empty?

            Loaders::TeamDescendants.load_all(teams, immediate_only: false).then do |descendant_ids_by_parent_id|
              descendant_ids_by_parent_id.to_a.flatten.compact.uniq.sort
            end
          end
        end
      end

      # Internal: fetch the Team IDs for the list of Repository IDs.
      #
      # Returns a Hash{repository_id Integer => Array[team_id Integer...]}.
      def fetch(repo_ids)
        results = Hash.new { |h, k| h[k] = [] }

        abilities = ::Ability.distinct.where(
          actor_type: "Team",
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
