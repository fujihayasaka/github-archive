# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class DirectProjectTeamAbilities < Platform::Loader
      def self.load(project:, team:)
        self.for(project).load(team.id)
      end

      def initialize(project)
        @project = project
      end

      # Internal: Fetch the direct team abilities on the given project.
      #
      # Returns a Hash{team id => Ability}.
      def fetch(team_ids)
        ::Ability.where(
          actor_type: "Team",
          actor_id: team_ids,
          subject_type: "Project",
          subject_id: @project.id,
          priority: ::Ability.priorities[:direct],
        ).index_by(&:actor_id)
      end
    end
  end
end
