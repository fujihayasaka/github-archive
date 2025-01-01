# typed: true
# frozen_string_literal: true

require "gh/interfaces/git_rpc"

module Repository::RpcDependency
  extend T::Helpers

  requires_ancestor { Repository }

  include GH::Interfaces::GitRPC

  UnroutedError = Class.new(StandardError)

  # Public: The GitRPC::Client object used to retrieve git objects and
  # perform repository commands. The client is configured to cache aggressively.
  #
  # See https://github.com/github/gitrpc for project information.
  #
  # Returns the cached GitRPC::Client object associated with this repository.
  def rpc
    return @rpc if @rpc
    @rpc = build_rpc
  end

  def async_rpc
    return @async_rpc if defined?(@async_rpc)
    @async_rpc = async_network.then do
      rpc
    end
  end

  # Public: Constructs a brand new GitRPC::Client object based on this repository.
  #
  # Returns a new instance of GitRPC::Client associated with this repository
  def build_rpc
    raise UnroutedError, "Repo id #{id} has no network" if network.nil?

    rpc = GitRPC.new(
      "dgit:/",
      delegate: dgit_delegate,
      lazy_cache: GitHub.lazy_cache
    )
    setup_rpc(rpc)
  end

  def extend_rpc_alternates(*repos)
    rpc.options[:alternates] = T.unsafe(self).alternate_object_paths_for(*repos)
  end

  # A GitRPC object to use for removing a repository and its replicas.
  #
  # This will not report any disagreements.
  def removal_rpc
    @removal_rpc ||=
      GitRPC.new("dgit:/", delegate: GitHub::DGit::Delegate::RepositoryRemoval.new(network_id, id, no_dgit_shard_path))
  end

  # Array of remote git repository paths to include as alternate object
  # stores. This is necessary when performing operations that cross
  # repositories.
  #
  # Returns an array of paths.
  def alternate_object_paths_for(*repos)
    paths = [self, *repos].compact.map(&:shard_path)
    paths << self.network&.shared_storage_path if self.network&.shared_storage_enabled?
    paths.compact.
      reject { |path| path == self.shard_path }.
      map { |path| "#{path}/objects" }.uniq
  end

  # Perform all RPC operations as if this repo lived in a different
  # network.  This is useful for repos that are being extracted or moved.
  # It only has an effect on DGit repos -- the same effect can be
  # accomplished for non-DGit repos by overriding the network_id.
  def set_rpc_network_override(network)
    ret = GitRPC.new(
      "dgit:/",
      delegate: GitHub::DGit::Delegate::Network.new(network.id, no_dgit_shard_path),
    )
    @rpc = setup_rpc(ret)
  end

  def setup_rpc(r)
    r.content_key = "gitrpc:#{network_cache_key}"
    r.repository_key = "gitrpc:#{repository_cache_key}"
    setup_rpc_options(r)
  end
  private :setup_rpc

  def setup_rpc_options(r)
    r.feature_enabled = self.method(:feature_enabled?)
    r.options[:info] = {
      user_id: GitHub.context[:actor_id],
      real_ip: GitHub.context[:actor_ip],
      request_id: GitHub.context[:request_id],
      repo_id: self.id,
      repo_name: self.name_with_owner,
    }
    if GitHub.context[:from]
      r.options[:info][:from] = GitHub.context[:from]
    elsif GitHub.context[:job]
      r.options[:info][:from] = GitHub.context[:job]
    end

    r.options[:should_throttle_gitrpc] = GitHub.flipper[:throttle_expensive_gitrpc_calls].enabled?(self.network)

    if r.options[:info][:request_id].blank? && GitHub.flipper[:gitrpc_always_include_request_id].enabled?(self.network)
      r.options[:info][:request_id] = GitHub.context[:aqueduct_job_id] || "#{Process.pid}-#{Time.now.to_i}-#{(rand * 10000).to_i}"
    end

    if trace2_enabled?
      r.options[:trace2] = [:blame_tree, :nw_repack, :nw_gc]
    end
    r
  end
  private :setup_rpc_options

  def wiki_shard_path
    no_dgit_shard_path.sub(/(?<!\.wiki)\.git$/, ".wiki.git")
  end

  WIKI_RPC_CACHE_VERSION = 1

  # Intentionally not memoized here - it's memoized in GitHub::Unsullied::Wiki
  # instead. This preserves existing `repo.wiki(true).rpc` semantics to avoid
  # breaking code which relies on that refreshing the wiki rpc object.
  def wiki_rpc!
    wiki_rpc = GitRPC.new(
      "dgit:/",
      delegate: dgit_wiki_delegate,
    )
    wiki_rpc.content_key = "gitrpc:wc:v#{WIKI_RPC_CACHE_VERSION}:#{id}"
    wiki_rpc.repository_key = "gitrpc:w:v#{WIKI_RPC_CACHE_VERSION}:#{id}"

    setup_rpc_options(wiki_rpc)
  end

  # Public: The collection object used to read Commit, Blob, Tree, and Tag
  # objects from the repository.
  #
  # Returns a RepositoryObjectsCollection bound to this repository.
  def objects
    @objects ||= RepositoryObjectsCollection.new(self)
  end

  # Public: All submodules for this repository at the given sha.
  #
  # oid - The commit oid to fetch the submodules for.
  #
  # Returns: A hash keyed by submodule paths, with Submodule objects
  def submodules(oid)
    async_submodules(oid).sync
  end

  # Public: fetch a submodule at an oid based on the path to the submodule.
  #
  # oid  - The commit oid to fetch the submodule for.
  # path - The path in the repo the submodule is in.
  #
  # Returns: A Submodule object
  def submodule(oid, path)
    async_submodule(oid, path).sync
  end

  # Public: async version of #submodule.
  def async_submodule(oid, path)
    async_submodules(oid).then do |submodules|
      submodules[path.gsub(%r{\A/+}, "")]
    end
  end

  # Public: async version of #submodules.
  def async_submodules(oid)
    @submodules ||= {}
    if @submodules[oid]
      return Promise.resolve(@submodules[oid])
    end
    async_rpc.then do |rpc|
      @submodules[oid] = rpc.read_submodules(oid).each.with_object({}) do |submodule_data, all|
        all[submodule_data["path"]] = Submodule.new(
          superproject_repository: self,
          superproject_commit_oid: oid,
          submodule_data: submodule_data,
        )
      end
    end
  end

  # Cache key unique to this repository. This is used as a cache prefix for
  # repository scope objects.
  def repository_cache_key
    "r:#{id}:#{network&.cache_version_number}"
  end

  # Cache key unique to the repository's network used for caching all content
  # addressable git objects. Private repositories always have their own cache
  # space. Public repositories share cache space with all other public
  # repositories in the same network.
  def network_cache_key
    if !public?
      repository_cache_key
    else
      "n:#{network_id}:#{network&.cache_version_number}"
    end
  end

  def spokes_cache_key
    network_cache_key
  end

  # Increment the cache version on the root of this repository's network. This
  # causes cache keys for all members of the network to change. Used to
  # invalidate the entire git cache for all repositories in cases where secret
  # data was removed from a repo but still exists in the caches.
  def increment_cache_version!
    @rpc = nil
    network&.increment_cache_version!
  end
end
