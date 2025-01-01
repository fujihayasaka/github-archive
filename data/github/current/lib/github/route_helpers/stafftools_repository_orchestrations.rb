# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    def gh_stafftools_repository_repository_orchestrations_path(repo)
      expand_nwo_from :stafftools_repository_repository_orchestrations_path, repo
    end

    def gh_stafftools_repository_repository_orchestration_path(repository_orchestration)
      expand_from_repository_orchestration :stafftools_repository_repository_orchestration_path, repository_orchestration
    end

    def expand_from_repository_orchestration(helper, repository_orchestration)
      repo = repository_orchestration.repository
      send(helper, repo.owner, repo.name, repository_orchestration.id)
    end
  end
end
