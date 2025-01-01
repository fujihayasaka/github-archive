# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Remove the repository from disk as with rm -rf and also
    # remove the remote from network.git if the repository is linked.
    #
    # Returns nil on success, or raises GitRPC::CommandFailed on failure.
    def nw_rm
      send_message(:nw_rm)
    end

    # Public: Test whether this repository is linked to a network.git repository.
    #
    # Returns true or false.
    def nw_linked?
      send_message(:nw_linked?)
    end

    # Public: Synchronize all repositories in the network and run git-gc in network.git.
    #
    # log                        - log
    # root_network               - root network
    # window_byte_limit          - set 'pack.windowByteLimit' to the given value
    #                              in 'git-repack(1)'.
    # geometric                  - repack into a geometric progression
    # pristine                   - expire all reflogs and force full gc to remove unreachable objects
    # auto                       - automatically decide whether a repack is needed or not
    # max_cruft_size             - sets the maximum size of a cruft pack in bytes
    # Returns the result of the command.
    def nw_gc(options = {})
      send_message(:nw_gc, **options)
    end

    # Public: Enable shared network storage for this repository.
    #
    # Returns nil on success, or raises GitRPC::CommandFailed on failure.
    def nw_link
      send_message(:nw_link)
    end

    # Public: Synchronize changes from this repository into the linked network.git repository.
    #
    # Returns nil on success, or raises GitRPC::CommandFailed on failure.
    def nw_sync
      send_message(:nw_sync)
    end

    # Public: Disable object storage sharing with a network.git alternate repository.
    #
    # Returns nil on success, or raises GitRPC::CommandFailed on failure.
    def nw_unlink
      send_message(:nw_unlink)
    end

    # Public: Run `git repack` in safe mode.
    #
    # window_byte_limit          - set 'pack.windowByteLimit' to the given value
    #                              in 'git-repack(1)'.
    # geometric                  - repack into a geometric progression
    # max_cruft_size             - sets the maximum size of a cruft pack in bytes
    #
    # Returns nil on success, or raises GitRPC::CommandFailed on failure.
    def nw_repack(options = {})
      send_message(:nw_repack, **options)
    end

    # Public: Run `git nw-fsck` on the repo
    def nw_fsck(options = {})
      send_message(:nw_fsck, **options)
    end

    # Public: Run git-fsck and/or retrieve ouput from the last git-fsck.
    #
    # never - Do not run git-fsck even when file doesn't exist
    # force - Force git-fsck and write new file even if exists
    #
    # Returns the result of the command.
    def last_fsck(options = {})
      send_message(:last_fsck, **options)
    end

    # Public: Clean up messes and make small repairs within git repositories.
    #
    # fix                - Try to fix any problems that are found
    # type               - [network|fork|wiki|gist]
    # ignore_hooks       - ignore the "hooks" entry.
    # no_check_ownership - do not attempt to check ownership (requires git user)
    #
    # Returns the result of the command.
    def janitor(options = {})
      send_message(:janitor, **options)
    end
  end
end
