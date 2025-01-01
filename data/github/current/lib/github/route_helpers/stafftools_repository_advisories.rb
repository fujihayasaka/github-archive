# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    def gh_stafftools_repository_advisories_path(repo)
      expand_nwo_from :stafftools_repository_repository_advisories_path, repo
    end

    def gh_stafftools_repository_advisory_path(advisory)
      expand_from_advisory :stafftools_repository_repository_advisory_path, advisory
    end

    def gh_database_stafftools_repository_advisory_path(advisory)
      expand_from_advisory :database_stafftools_repository_repository_advisory_path, advisory
    end

    private

    def expand_from_advisory(helper, advisory)
      repo = advisory.repository
      send(helper, repo.owner, repo.name, advisory.id)
    end

  end
end
