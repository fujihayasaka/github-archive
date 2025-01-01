# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class TemplateRepositories < Platform::Resolvers::Repositories
      def repository_finder_type
        RepositoriesFinder::REPO_TYPE_TEMPLATE
      end
    end
  end
end
