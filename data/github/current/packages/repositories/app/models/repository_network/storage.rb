# typed: true
# frozen_string_literal: true

class RepositoryNetwork
  # Git access and storage management for repository networks. This is mixed
  # into RepositoryNetwork and provides methods for accessing and managing the
  # shared git repository storage area.
  #
  # The #host attribute stored on RepositoryNetwork records
  # dictates the storage host for all repositories in the network.
  module Storage
    extend T::Helpers

    requires_ancestor { RepositoryNetwork }
    # The network's storage URL as a "<host>:<path>" string. The <path> is to the
    # "network.git" directory.
    #
    # Returns a string fs URL string.
    def shared_storage_url
      GitHub::DGit::Routing.all_network_replicas(id).first.to_route(shared_storage_path).remote_url
    end

    # The full path to the directory that contains this network's git repositories,
    # including network.git and <repo-id>.git * each repository in the network.
    #
    # Returns a path string. "/data/repositories/1/nw/1d/cc/57/117302"
    def storage_path
      raise GitHub::DGit::UnroutedError if id.nil?
      @storage_path ||= GitHub::Routing.nw_storage_path(network_id: id)
    end

    # The full path to the network.git repository directory.
    #
    # Returns a path string. "/data/repositories/1/nw/1d/cc/57/117302/network.git"
    def shared_storage_path
      "#{storage_path}/network.git"
    end

    def dgit_mapped_shared_storage_path
      "#{dgit_mapped_storage_path}/network.git"
    end

    def dgit_mapped_storage_path
      if Rails.env.development? || Rails.env.test?
        first_host = GitHub::DGit::Routing.hosts_for_network(id).first
        GitHub::DGit.dev_route(storage_path, first_host)
      else
        storage_path
      end
    end

    # Does this network share object data in a network.git repository?
    #
    # Returns true if objects are shared between repositories in the network.
    def shared_storage_enabled?
      rpc.exist?
    rescue GitRPC::RepositoryOffline => e
      Failbot.report(e, app: "github-unrouted", "gh.repo.network_id": id)
      false
    end

    # Turn shared storage on or off for all private repositories in the network.
    # Shared storage is enabled for private repositories only when all repositories
    # in the network are private. If any repositories are public, the private
    # repositories are dealternated.
    #
    # This method should be called any time the public / private visibility for
    # any repository in the network is changed.
    #
    # Returns nothing.
    def enable_or_disable_shared_storage_for_private_repositories
      repositories.private_scope.includes(:owner).each(&:enable_or_disable_shared_storage)
    end

    # Calculate disk usage for the entire network storage directory and store in
    # the disk_usage attribute. This may be run on any network, even if the
    # shared storage directory does not exist.
    #
    # When shared storage is enabled globally, this performs a du on the
    # directory that contains all of this network's repositories giving an
    # accurate physical usage number for the entire network. When shared storage
    # is disabled globally (Enterprise), we simply take the sum of disk_usage
    # recorded on each repository in the network.
    #
    # Returns the amount of physical disk used by the entire network in KBs.
    def calculate_disk_usage
      self.disk_usage = rpc.nw_usage
    end

    # Like calculate_disk_usage but also save the record.
    def calculate_disk_usage!
      calculate_disk_usage
      save!
    end

    # override the built-in disk_usage to enforce a load if the saved value is nil
    #
    # Returns the amount of physical disk used by the entire network in KBs.
    def disk_usage(load_if_nil = false)
      du = attributes["disk_usage"]
      if du.nil? && load_if_nil
        du = calculate_disk_usage
      end
      du
    end

    # Calculate the amount of free space on disk.
    #
    # Returns the amount of physical disk available in KBs
    def calculate_free_space
      rpc.free_space
    end

    # Optimize pack files in the shared storage repository. This rebuilds all
    # packs that have accumulated since the last maintenance into a single
    # optimized pack and builds bitmap indexes, unless 'geometric' is
    # specified. The 'geometric' case selects a small set of pack-files to
    # repack and collect all under a multi-pack-index and bitmap.
    #
    # Incremental commit-graph files are given the same treatment, if the root
    # has this feature enabled.
    #
    # No objects are pruned during the
    # repack so this method can be used to safely optimize pack storage without
    # any risk of repository corruption.
    def repack(geometric: false)
      GitRPC::Util.with_repack_error_handler do
        # Timeouts are handled on a per rpc client level, explicitly run `nw_gc` with a 3 hour upper boundary
        # See also `GitHub::Jobs::NetworkMaintenance` as the most likely calling party
        rpc.with_timeout(3.hours) do
          rpc.nw_gc(log: true, root_network: root&.id, geometric: geometric,
                    max_cruft_size: root&.max_cruft_size)
        end
      end
    end

    # GitRPC::Client object connected to the shared storage network.git
    # repository. The repository is not guaranteed to exist and won't in
    # networks with only a single repository.
    #
    # See the GitRPC documentation for information on available calls:
    #
    # https://github.com/github/gitrpc/docs
    #
    # Returns a GitRPC::Client object.
    def rpc
      @rpc ||= scoped_rpc(shard_path)
    end

    # GitRPC::Client object connected to the network's parent directory,
    # in which network.git and all {id}.git and {id}.wiki.git
    # subdirectories reside.
    #
    # This is useful needed for *creating* new network.git, {id}.git, and
    # {id}.wiki.git repositories.
    #
    # Returns a GitRPC::Client object.
    def parent_rpc
      scoped_rpc(storage_path)
    end

    # Private helper function for `rpc` and `parent_rpc`, above -- create
    # a GitRPC::Client object bound to the requested directory.
    def scoped_rpc(path)
      rpc = GitRPC.new(
        "dgit:/",
        delegate: GitHub::DGit::Delegate::Network.new(id, path),
      )

      rpc.content_key = "gitrpc:n#{id}"
      rpc.repository_key = "gitrpc:n#{id}"
      rpc.feature_enabled = self.method(:feature_enabled?)
      rpc.options[:info] = {
        real_ip: GitHub.context[:actor_ip],
        request_id: GitHub.context[:request_id],
        repo_id: id
      }
      if rpc.options[:info][:request_id].blank? && GitHub.flipper[:gitrpc_always_include_request_id].enabled?(T.cast(self, RepositoryNetwork))
        rpc.options[:info][:request_id] = GitHub.context[:aqueduct_job_id] || "#{Process.pid}-#{Time.now.to_i}-#{(rand * 10000).to_i}"
      end
      if GitHub.context[:from]
        rpc.options[:info][:from] = GitHub.context[:from]
      elsif GitHub.context[:job]
        rpc.options[:info][:from] = GitHub.context[:job]
      end
      rpc
    end
    private :scoped_rpc

    # Raised when a copy fork operation fails.
    class CopyForkFailed < StandardError
    end

    # Internal: Move the given repositories into this network.
    #
    # Returns nothing.
    def move_repositories_into_network(repositories, network)
      GitHub.dogstats.increment "storage", tags: ["action:move_repositories_into_network"]
      GitHub.logger.info(
        "Moving repositories into network",
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.repo.network_id" => network.id,
        "gh.repo.move_netowrk.old_network_and_repo" => repositories.map { |repo| "#{repo.network.id}/#{repo.id}" }
      )

      repositories.each do |repo|
        begin
          repo.disable_shared_storage
        rescue Exception => e # rubocop:todo Lint/GenericRescue
          Failbot.report(e, { "gh.repo.id": repo.id })
        end
      end
      GitHub::BatchRepositoryTransfer.new(network, repositories).perform
    end

    private

    # Internal: Get a list of ids and wiki ids to pass
    # to git copy-fork calls from the given list of
    # repositories.
    #
    # Returns an array of string ids and wiki ids.
    def repo_and_wiki_ids(repositories)
      repositories.map do |repo|
        if repo.wiki_exists_on_disk?
          [repo.id.to_s, "#{repo.id}.wiki"]
        else
          repo.id.to_s
        end
      end.flatten
    end
  end
end
