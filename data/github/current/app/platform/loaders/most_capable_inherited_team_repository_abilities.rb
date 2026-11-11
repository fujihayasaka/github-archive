# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class MostCapableInheritedTeamRepositoryAbilities < Platform::Loader
      def self.load(team:, repo:)
        self.for(team).load(repo.id)
      end

      def initialize(team)
        @team = team
      end

      # Internal: Fetch the most capable abilities for the given repos.
      #
      # Returns a Hash{repo Id => Ability}.
      def fetch(repo_ids)
        abilities = ::Ability.where(
          actor_type: Team,
          actor_id: @team.ancestor_ids,
          subject_type: Repository,
          subject_id: repo_ids,
          priority: ::Ability.priorities[:direct],
        )

        select_most_capable_ability_for_subject(abilities)
      end

      # Internal: Selects the most capable abilities for each repo ignoring
      # which team the permission came from.
      #
      # abilities - [Ability]
      #
      # Returns a Hash{repo Id => Ability}.
      def select_most_capable_ability_for_subject(abilities)
        abilities.each_with_object({}) do |ability, result|
          subject_id = ability.subject_id

          if !result.key?(subject_id) || ability > result[subject_id]
            result[subject_id] = ability
          end
        end
      end
    end
  end
end
