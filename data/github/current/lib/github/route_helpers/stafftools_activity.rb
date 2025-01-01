# typed: false
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    def gh_stafftools_repository_activity_path(repo, options = nil)
      stafftools_repository_activity_path(repo.owner, repo, options)
    end
  end
end
