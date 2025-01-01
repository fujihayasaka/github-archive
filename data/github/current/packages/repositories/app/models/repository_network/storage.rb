# typed: false
# frozen_string_literal: true

class RepositoryNetwork
  # Git access and storage management for repository networks. This is mixed
  # into RepositoryNetwork and provides methods for accessing and managing the
  # shared git repository storage area.
  #
  # The #host attribute stored on RepositoryNetwork records
  # dictates the storage host for all repositories in the network.
  module Storage
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

    # Calculate the disk usage for the given subset of the network.
    #
    # See git copy-fork --estimate-size and git size-forks --cumulative
    # for more information on how this is calculated.
    #
    # Returns an estimate of the physical disk usage of the given
    # subset of the network in KBs.
    def disk_usage_of_forks(forks)
      rpc.estimate_copy_fork(repo_and_wiki_ids(forks))
    rescue GitRPC::CommandFailed => e
      raise CopyForkFailed.new(e)
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
          rpc.nw_gc(log: true, root_network: root.id, geometric: geometric)
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
      if rpc.options[:info][:request_id].blank? && GitHub.flipper[:gitrpc_always_include_request_id].enabled?(self)
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

    # Helper class for moving repositories from one
    # RepositoryNetwork into another during extraction.
    #
    # Usage:
    #         extraction = Extraction.new(old_network, new_network, [repo, repo2])
    #         extraction.extract!
    #
    class Extraction
      attr_accessor :original_repos, :copy_repos

      def initialize(old_network, new_network, repositories)
        @original_network = old_network
        @copy_network = new_network
        @original_repos = repositories
        @copy_repos = new_repositories_for_copy
      end

      # Public: Copy the repositories into the new network
      # using `git copy-fork`.
      #
      # Returns nothing.
      #
      # Raises Repository::CommandFailed if there was a problem
      # with the repositories that prevented copying.
      # Raises CopyForkFailed if there was an error during copying.
      def extract!
        return unless @original_repos.size > 0

        @original_network.rpc.nw_gc(geometric: false)

        prepare_old_repositories_for_copy

        begin
          prepare_new_network_for_copy
          @copy_network.prepare_copy(@original_network.shared_storage_url, @original_repos)

          @original_repos.each do |old_repo|
            old_repo.lock_for_move
            @copy_network.copy_fork(@original_network.shared_storage_url, old_repo)

            old_repo.update_network(@copy_network)
            old_repo.update_default_branch(old_repo.default_branch)

            old_repo.unlock_including_descendants!
          end
        rescue GitRPC::CommandFailed, ::Repository::CommandFailed, CopyForkFailed, GitHub::DGit::ChecksumInitError => f
          clean_up_failed_copy
          raise f
        end

        unless @original_repos.size == 1
          @copy_network.rpc.nw_gc(geometric: false)
        end

        #@original_repos.each do |repo|
        # don't remove the old repo yet while we're testing this out
        # @original_network.rpc.spawn_git("nw-rm", [repo.id.to_s])
        #end

        if @original_network.reload.repositories.size == 1
          @original_network.root.disable_shared_storage
        end

        if @original_repos.size == 1
          @original_repos.first.disable_shared_storage
        end
      end

      private

      # Internal: Prepare each of the original repostiories for
      # extraction by cleaning up any old,
      # unused files and ensuring that it doesn't
      # contain any unidentified files that could
      # cause the copy to fail.
      def prepare_old_repositories_for_copy
        @original_repos.each do |repo|
          repo.janitor_fix
          out = repo.rpc.unknown_files
          raise Repository::CommandFailed.new(out) if out
        end
      end

      # Internal: Prepare the new network for the copy by
      # creating empty git repositories on disk
      # for each of the repositories and wikis
      # to be copied.
      #
      # Raises Repository::CommandFailed if there
      # is a problem creating the empty repositories.
      def prepare_new_network_for_copy
        @copy_repos.each do |dup|
          # setup an empty #{repo.network_id}/#{repo.id}.git
          # stolen from Repository#setup_git_repository
          # leaving out bits like routing and forking if the repo
          # has a parent since we don't want that in this case
          dup.create_git_repository_on_disk

          if dup.has_wiki? && dup.unsullied_wiki
            # Don't call Unsullied::Wiki#create_git_repository_on_disk
            # here, as it might try to fork from a parent that hasn't been
            # copied yet.  We want an empty wiki repo to fetch into.
            creator =
              GitHub::RepoCreator.new(dup.unsullied_wiki,
                public: dup.public?,
                template: GitHub.repository_template,
                nwo: "#{dup.name_with_owner}.wiki")
            creator.init
          end

          dup.initialize_git_repository_templates

          dup.enable_shared_storage
        end
      end

      # Internal: remove the copied repos from disk
      # when an extraction fails and ensure that
      # the original repos are still pointing at the
      # original network
      # TODO: remove wiki repos too?
      def clean_up_failed_copy
        @copy_repos.each do |repo|
          repo.remove_from_disk
        end

        @original_repos.each do |repo|
          if repo.network_id == @copy_network.id
            repo.set_network(@orginal_network)
          end

          repo.unlock_including_descendants! if repo.locked_on_move?
        end
      end

      # Returns an array of frozen repository objects
      # pointing at the new network that can be used
      # to set up new empty git repositories on disk.
      def new_repositories_for_copy
        original_repos.map do |repo|
          dup = repo.dup

          # dup doesn't copy id, but we need it to set up
          # the git repo with the right name
          dup.id = repo.id
          # raw_data doesn't get dup'd since it's added by
          # serialized_attributes when it extends AR::Base,
          # but we need raw_data because gitignore_template
          # is a serialized attribute
          dup.raw_data = ""

          dup.network_id = @copy_network.id
          dup.reset_git_cache
          dup.set_rpc_network_override(@copy_network)

          if repo.unsullied_wiki.exist?
            # do a hard refresh of the cached wiki object
            dup.unsullied_wiki(true)
            dup.unsullied_wiki.set_rpc_network_override(@copy_network)
          else
            dup.has_wiki = false
          end
          dup.freeze

          dup
        end
      end
    end

    def prepare_copy(old_network_location, repositories)
      repo_list = repo_and_wiki_ids(repositories)

      begin
        rpc.prepare_copy_fork(old_network_location, repo_list)
      rescue GitRPC::CommandFailed => e
        raise CopyForkFailed.new(e)
      end
    end

    def copy_fork(old_network_location, fork)
      rpc.copy_fork(old_network_location, fork.id.to_s)
      if fork.wiki_exists_on_disk?
        rpc.copy_fork(old_network_location, "#{fork.id}.wiki")
      end
    rescue GitRPC::CommandFailed => e
      raise CopyForkFailed.new(e)
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
