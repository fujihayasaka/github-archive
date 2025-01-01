# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class MostCapableTeamRepositoryAbilities < Platform::Loader
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
        @team.most_capable_abilities_on_subjects(repo_ids, subject_type: ::Repository)
      end
    end
  end
end
