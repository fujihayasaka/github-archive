# typed: false
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    def gh_stafftools_repository_repository_files_path(repo)
      expand_nwo_from :stafftools_repository_repository_files_path, repo
    end

    def gh_stafftools_repository_repository_file_path(file)
      repo = file.repository
      stafftools_repository_repository_file_path(repo.owner, repo, file)
    end

    def gh_database_stafftools_repository_repository_file_path(file)
      repo = file.repository
      database_stafftools_repository_repository_file_path(repo.owner, repo, file)
    end

  end
end
