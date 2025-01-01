# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Fetch commit from <repo> into the current repository.
    #
    # src_path              - path to fetch from
    # quiet                 - quiet
    # no_tags               - don't fetch tags
    # force                 - force
    # prune                 - remove any remote-tracking refs that don't exist on remote
    # no_recurse_submodules - disable recursive fetching of submodules
    # refspec               - which refs to fetch
    #
    # Returns a Hash with "out" and "err" keys, or raises GitRPC::CommandFailed.
    def fetch(src_path, options = {})
      send_message(:fetch, src_path, **options)
    end

    # Public: Fetch commit from <repo> into the current repository.
    #
    # repo       - a repo path
    # commit_oid - a commit
    #
    # Returns nil, or raises GitRPC::CommandFailed.
    def fetch_commits(repo, commit_oid)
      ensure_valid_full_oid(commit_oid)

      send_message(:fetch_commits, repo, commit_oid)
    rescue GitRPC::Protocol::DGit::ResponseError => e
      if GitRPC.test_tracer
        raise e.class, GitRPC.test_tracer.append_calls_to_error_message(e.message)
      end
      raise
    end

    # Public: Clone the current repository at <newid>.git under the same network directory.
    #
    # branch              - point new repository's HEAD at this branch
    # template            - template dir
    # newid               - new repository id
    # one_branch          - create a single branch with no tags
    #
    # Returns nil, or raises GitRPC::CommandFailed.
    def nw_clone(branch, template, newid, one_branch)
      send_message(:nw_clone, branch, template, newid, one_branch: one_branch)
    end

    # Public: Create a bare clone of the source repository.
    #
    # src  - source
    # dest - destination
    #
    # Returns nil or raises GitRPC::CommandFailed.
    def bare_clone(src, dest)
      send_message(:bare_clone, src, dest)
    end
  end
end
