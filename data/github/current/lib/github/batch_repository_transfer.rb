# typed: true
# frozen_string_literal: true

module GitHub
  # Transfers a number of repositories from their current network disk
  # location(s) to new network disk location(s), possibly on other
  # machine(s).
  #
  # Due to DGit, there may be ~3 sources and ~3 destinations.  One source
  # is chosen to perform the copy, which may be different for each repo.
  # All sources are deleted upon successful completion.
  #
  # This is used primarily to move a subset of repositories out of one network and
  # into another. It shouldn't be used to move whole networks since it currently
  # moves repositories one at a time. Moving a whole network can be done much
  # more efficiently with script/move_network.
  class BatchRepositoryTransfer
    # Array of repository objects to transfer from their current disk
    # location(s) to the target network's disk location(s). This may
    # include many repositories.
    attr_reader :repositories

    # The RepositoryNetwork object for the target network where all
    # repositories should be transferred.
    attr_reader :target_network

    # Set up a transfer of repositories from their current disk
    # location(s) to another network's disk location(s). See the attribute
    # documentation above for argument requirements.
    #
    # Once the object is constructed, the #perform method can be used to
    # transfer everything in a single call. The #prepare_target, #transfer_entries,
    # and #remove_entries may be used instead to control
    def initialize(target_network, repositories)
      @target_network = target_network
      @repositories = repositories.delete_if { |repo| repo.network.id == target_network.id }
    end

    # Public: Transfer the on-disk state of the given repositories to the
    # target network location. This performs the prepare, transfer,
    # verify, and remove steps in a single call.  Verification is done as
    # part of the transfer step.
    #
    # Returns self.
    def perform
      prepare_targets
      transfer_entries
      remove_entries
      self
    end

    # Public: Ensure the target network directory exists. This creates the
    # directory if it's not already there.  On a DGit network, this hits
    # all destinations.
    def prepare_targets
      target_network.rpc.create_network_dir
    end

    # Public: Transfer all matching repository directories from the source
    # network location to the target network location, and verify that
    # they were moved correctly.  On DGit, this copies from the best
    # healthy reader to all replicas hosting the target network.
    def transfer_entries
      @repositories.each do |repo|
        repo.rpc.push_to(target_urls) if repo.rpc.exist?
        if repo.has_wiki? && repo.unsullied_wiki.exist?
          repo.unsullied_wiki.rpc.push_to(target_urls)
        end
      end
    end

    # Public: Remove all paths from the source network directory. This
    # should be called only after the transfer is complete and verified.
    # On DGit, this removes the repositories from their original
    # repo-network directory on all replicas.
    def remove_entries
      @repositories.each do |repo|
        repo.rpc.remove if repo.rpc.exist?
        if repo.has_wiki? && repo.unsullied_wiki.exist?
          repo.unsullied_wiki.rpc.remove
        end
      end
    end

    # Internal: full URLs to all target directories.  For example,
    # "10.1.2.3:/data/repositories/f/nw/f8/a7/cc/54321"
    #
    # Returns an array of strings, each of which is a URL that hosts the
    # target network.  On DGit, this is ~3 strings.  On legacy storage,
    # it's only one.
    def target_urls
      return @target_urls if defined?(@target_urls)

      delegate = GitHub::DGit::Delegate::Network.new(target_network.id,
                                                     target_network.storage_path)
      @target_urls = delegate.get_write_routes.map { |route| route.rsync_url }
    end
  end
end
