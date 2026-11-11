# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    def gh_purge_objects_stafftools_repository_large_files_path(repo)
      expand_nwo_from :purge_objects_stafftools_repository_large_files_path, repo
    end

    def gh_restore_objects_stafftools_repository_large_files_path(repo)
      expand_nwo_from :restore_objects_stafftools_repository_large_files_path, repo
    end
  end
end
