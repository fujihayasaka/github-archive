# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class MostCapableInheritedTeamProjectAbilities < Platform::Loader
      def self.load(team:, project:)
        self.for(team).load(project.id)
      end

      def initialize(team)
        @team = team
      end

      # Internal: Fetch the most capable abilities for the given projects.
      #
      # Returns a Hash{project Id => Ability}.
      def fetch(project_ids)
        abilities = ::Ability.where(
          actor_id: @team.ancestor_ids,
          actor_type: "Team",
          subject_id: project_ids,
          subject_type: "Project",
          priority: ::Ability.priorities[:direct],
        )

        select_most_capable_ability_for_subject(abilities)
      end

      # Internal: Selects the most capable abilities for each project ignoring
      # which team the permission came from.
      #
      # abilities - [Ability]
      #
      # Returns a Hash{project Id => Ability}.
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
