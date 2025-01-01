# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Estimate the size of the given repositories in this network.
    # Must be called from a network.git repostiory.
    #
    # repositories       - Array of string repository or wiki ids in
    #                      the network whose size to estimate.
    #
    # See git-copy-fork --estimate-size for more info.
    #
    # Returns an estimate of the physical disk usage of the given
    # subset of the network in KBs, or raises GitRPC::CommandFailed.
    def estimate_copy_fork(repositories)
      send_message(:estimate_copy_fork, repositories)
    end

    # Pre-copy forks from the given network into this network.
    # Must be called from a network.git repository.
    #
    # source_network_url - The "<host>:<path>" location of the network to
    #                      transfer the repositories from.
    # repositories       - Array of string repository ids to transfer from
    #                      the source network into the current network.
    #
    # See git-copy-fork --prepare for more info.
    #
    # Returns nil or raises GitRPC::CommandFailed.
    def prepare_copy_fork(source_network_url, repositories)
      repos = Array(repositories)
      if repos.empty?
        raise ArgumentError, "prepare_copy_fork requires at least one repository to copy"
      end

      send_message(:prepare_copy_fork, source_network_url, repositories)
    end

    # Copy the given fork from the given network into this network.
    # Must be called from a network.git repository.
    #
    # source_network_url - The "<host>:<path>" location of the network to
    #                      transfer the repository from.
    # repository         - String repository or wiki id to transfer from
    #                      the source network into the current network.
    #
    # See git-copy-fork for more info.
    #
    # Returns nil or raises GitRPC::CommandFailed.
    def copy_fork(source_network_url, repository)
      send_message(:copy_fork, source_network_url, repository)
    end

    # Check whether there are any unknown files in this repository
    # (as determined by `git copy-fork --list-unknown-files`).
    #
    # Returns a string describing the unknown files, or nil if none.
    def unknown_files
      send_message(:unknown_files)
    end
  end
end
