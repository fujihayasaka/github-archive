# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    # GETs
    def gh_stafftools_repository_redirects_path(repo)
      expand_nwo_from :stafftools_repository_redirects_path, repo
    end

  end
end
