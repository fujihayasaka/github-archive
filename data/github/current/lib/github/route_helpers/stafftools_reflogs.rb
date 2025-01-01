# typed: false
# frozen_string_literal: true

module GitHub
  module RouteHelpers

    def gh_stafftools_repository_reflog_path(repo)
      expand_nwo_from :stafftools_repository_reflog_path, repo
    end

    def gh_deleted_stafftools_repository_reflog_path(repo)
      expand_nwo_from :deleted_stafftools_repository_reflog_path, repo
    end

    def gh_force_pushes_stafftools_repository_reflog_path(repo)
      expand_nwo_from :force_pushes_stafftools_repository_reflog_path, repo
    end

    def gh_restore_stafftools_repository_reflog_path(repo, ref, oid)
      restore_stafftools_repository_reflog_path \
        repo.owner, repo, ref: ref, oid: oid
    end

    def gh_sync_stafftools_repository_reflog_path(repo)
      expand_nwo_from :sync_stafftools_repository_reflog_path, repo
    end

  end
end
