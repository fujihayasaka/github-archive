# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class MostCapableTeamProjectAbilities < Platform::Loader
      def self.load(team:, project:)
        self.for(team).load(project.id)
      end

      def initialize(team)
        @team = team
      end

      # Internal: Fetch the direct project abilities for the given team.
      #
      # Returns a Hash{project id => Ability}.
      def fetch(project_ids)
        @team.most_capable_abilities_on_subjects(project_ids, subject_type: ::Project)
      end
    end
  end
end
