# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    def gh_stafftools_repository_mirror_path(repo)
      expand_nwo_from :stafftools_repository_mirror_path, repo
    end

    def gh_sync_stafftools_repository_mirror_path(repo)
      expand_nwo_from :sync_stafftools_repository_mirror_path, repo
    end

  end
end
