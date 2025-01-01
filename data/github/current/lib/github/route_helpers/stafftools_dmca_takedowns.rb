# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    def gh_stafftools_repository_dmca_takedown_path(repo)
      expand_nwo_from :stafftools_repository_dmca_takedown_path, repo
    end

  end
end
