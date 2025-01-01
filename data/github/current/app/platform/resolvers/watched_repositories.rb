# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class WatchedRepositories < Platform::Resolvers::Repositories
      BATCH_SIZE = 100

      argument :affiliations, [Enums::RepositoryAffiliation, null: true],
        required: false,
        description: "Affiliation options for repositories returned from the connection. If none specified, the results will include repositories for which the current viewer is an owner or collaborator, or member."

      private

      def repository_finder_type
        RepositoriesFinder::REPO_TYPE_WATCHED
      end

      def default_affiliations
        [:owned, :direct, :indirect]
      end
    end
  end
end
