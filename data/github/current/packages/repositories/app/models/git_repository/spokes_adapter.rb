# typed: false
# frozen_string_literal: true

# Defines methods that help transition from GitRPC to Spokes.
module GitRepository::SpokesAdapter
  include Scientist

  #### Pre-Spokes transition methods ####

  # Outside of tests, this function is essentially a no-op, always returning
  # 'false' and  allowing the libgit2 -> git tests to run as usual.
  #
  # In some tests, we check the number of calls made to GitRPC. In these cases,
  # the double-calls of the experiments will trigger failure. This function
  # should be mocked to return 'true' for those tests.
  def disable_libgit2_to_git_experiments; false; end

  # Public: Read the reference pointed to by the symbolic HEAD reference.
  #
  # Returns a string containing the fully-qualified reference that HEAD points
  # to, or raises GitRPC::CommandFailed.
  def get_default_branch
    cache_key = repository_reference_cache_key("read_symbolic_ref", "HEAD")
    cache_fetch(cache_key, backend_method: :read_symbolic_ref) do
      science "get_default_branch_spokes_experiment" do |e|
        e.context({ repo_id: self.id })
        e.use { self.rpc.read_symbolic_ref("HEAD") }
        e.try { self.spokes_api.get_default_branch }
        e.compare_errors do |control, candidate|
          if candidate.is_a?(SpokesAPI::Error)
            # In callers, these error classes route to the same behavior.
            [
              GitRPC::Error,
              GitHub::DGit::UnroutedError,
              Repository::RpcDependency::UnroutedError
            ].any? { |err| control.is_a?(err) }
          else
            control.class == candidate.class && control.message == candidate.message
          end
        end
        e.run_if { self.id && GitHub.spokesd_enabled? }
      end
    end
  end

  # Public: Read the reference pointed to by the symbolic HEAD reference.
  #
  # Returns a Promise that resolves to a string containing the fully-qualified
  # reference that HEAD points to, or rejects the promise with
  # GitRPC::CommandFailed.
  def async_get_default_branch
    GitHub.cache.async_get_or_cache(repository_reference_cache_key("read_symbolic_ref", "HEAD")) do
      self.rpc.async_read_symbolic_ref("HEAD")
    end
  end

  # Public: Create a merge commit
  #
  # base           - the commit to merge into
  # head           - the commit to merge
  # author         - author information hash
  # commit_message - the message to use for the commit
  def create_merge_commit(base, head, author, commit_message, options = {}, &block)
    options = options.merge(use_tmp_objdir_mode: "migrate-on-success")

    if repository.feature_enabled?(:tmp_objdir_experiment)
      options = options.merge(dogstats: true)
      options[:use_tmp_objdir_mode] = "pack-and-migrate-on-success" if repository.feature_enabled?(:tmp_objdir_experiment_pack)
      if GitHub.flipper[:tmp_objdir_experiment_threshold].percentage_of_time_value > 0
        options[:keep_unpacked_threshold] = (GitHub.flipper[:tmp_objdir_experiment_threshold].percentage_of_time_value * 1000).floor.to_s
      end
    end

    result = self.rpc.create_merge_commit(base, head, author, commit_message, options, &block)
    result[4].each { |args| GitHub.dogstats.count(*args) } unless result[4].nil?
    result
  end

  def rev_parse(object_name)
    if repository.feature_enabled?(:rev_parse_spokes_api)
      self.spokes_api.resolve_object(object_name: object_name)
    else
      science "rev_parse_spokes_api_experiment" do |e|
        e.context({
          obejct_name: object_name,
          repository: repository
        })
        e.use { self.rpc.rev_parse(object_name) }
        e.try { self.spokes_api.resolve_object(object_name: object_name) }
        e.run_if { !disable_libgit2_to_git_experiments }
      end
    end
  end

  # Internal (tests only): All of the possible refs_keys
  def refs_keys
    GitRPC::Util::READ_REFS_FILTERS.map { |filter| refs_key(filter) }
  end

  #############################################################################

  #### In-transition methods ####

  def blame_tree(commit_oid, root = nil, recursive = true)
    GitRPC::Util.ensure_valid_full_sha1(commit_oid)

    key = content_cache_key("blame-tree", commit_oid, sha256(root), recursive, "v4")
    cache_fetch(key, backend_method: :blame_tree) do
      begin
        self.spokes_api.blame_tree(commit_oid, root, recursive)
      rescue SpokesAPI::TimedOut
        raise GitRPC::Timeout.new
      end
    end
  end

  def read_latest_wiki_pages(oid)
    if !GitRPC::Util.valid_full_sha1?(oid)
      raise ::GitRPC::InvalidFullOid, "wrong argument type #{oid.inspect} (expected 40c String OID)"
    end

    wiki_key = content_cache_key("latest-wiki-pages", oid, "v3")
    GitHub.cache.fetch(wiki_key) do
      entries = blame_tree(oid)

      commit_oids = []
      entries.select! do |path, commit_oid|
        filename = ::File.basename(path)
        if GitRPC::Backend.valid_wiki_page?(filename)
          commit_oids << commit_oid
        end
      end

      commits = {}
      self.rpc.read_commits(commit_oids.uniq).each do |commit|
        commits[commit["oid"]] = commit
      end

      pages = []
      entries.each do |path, commit_oid|
        commit = commits[commit_oid]
        pages << [path, commit]
      end

      pages.sort do |entry_a, entry_b|
        time1 = Time.at(*entry_a[1]["author"][2])
        time2 = Time.at(*entry_b[1]["author"][2])

        time2 <=> time1
      end

      pages.map do |entry, commit|
        [entry, commit["oid"]]
      end
    end
  end

  private

  # Internal: run and instrument GitHub.cache.fetch.
  def cache_fetch(key, *args, backend_method:)
    cache_result = "hit"
    GitHub.cache.fetch(key, *args) do
      cache_result = "miss"
      yield
    end
  ensure
    GitHub.instrument("cache_get.spokes_adapter", backend_method:, cache_result: cache_result)
  end

  # Internal: Generate a cache key for an immutable and content addressable
  # piece of content like a commit, tree, or blob. This uses the content_key
  # attribute as a base prefix. See the attribute docs for more info on
  # content addressable cache keys.
  #
  # parts - Array of additional stuff to include in the key. This must consist
  #         of valid memcache key characters only. Use the sha256 digest for path
  #         names and other elements that may include weird characters.
  #
  # Returns a string key suitable for use with memcache.
  def content_cache_key(*parts)
    [cache_version, spokes_cache_key, *parts].join(":")
  end

  # Internal: Generate a cache key for the repository's references. This key
  # changes whenever the repository's ref state changes.
  #
  # This intentionally differs from the equivalent GitRPC function by adding the
  # "spokes_adapter" element to the key. Doing so prevents cache poisoning in
  # situation where a method moved to SpokesAdapter returns bad results and
  # needs to be rolled back.
  #
  # parts - Array of additional cache key elements.
  #
  # Returns a string key suitable for use with memcache.
  def repository_reference_cache_key(*parts)
    [cache_version, "spokes_adapter", self.rpc.repository_key, self.rpc.repository_reference_key, *parts].join(":")
  end

  def cache_version
    "v2"
  end

  # Internal: Cache key used to store the main refs hash.
  def refs_key(filter)
    repository_reference_cache_key("refs", "v4", filter)
  end

  def spokes_cache_key
    if self.responds_to?(:spokes_cache_key)
      "spokes_adapter:#{self.spokes_cache_key}"
    else
      # If SpokesAdapter is included in more classes, the appropriate cases
      # must be added above to avoid this error
      raise "Unknown GitRPC cache key for #{self.class.name}"
    end
  end

  # Internal: Generate an sha256 sum of the passed strings. Used to
  # generate fixed length representation of variable length parameters
  # to be used as cache keys
  #
  # parts - Array of variable length keys to sha256sum
  #
  # Returns a sha256 hash string of the parameters
  def sha256(*parts)
    Digest::SHA256.hexdigest(parts.join(":"))
  end

end
