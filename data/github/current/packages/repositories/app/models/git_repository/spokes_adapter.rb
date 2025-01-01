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

  # Outside of tests, this function is essentially a no-op, always returning
  # 'false' and allowing the Spokes API operations to run as usual.
  #
  # In some tests, we synthesize fake data that exists in the database but
  # doesn't actually exist when accessed through spokesd, which can trigger
  # failures. This function should be mocked to return 'true' for those tests.
  def disable_spokes_api_conversions; false; end

  # Public: Read the reference pointed to by the symbolic HEAD reference.
  #
  # Returns a string containing the fully-qualified reference that HEAD points
  # to, or raises GitRPC::CommandFailed.
  def get_default_branch
    if self.id && GitHub.spokesd_enabled? && self.feature_enabled?(:get_default_branch_spokes)
      cache_key = repository_reference_cache_key("get_default_branch")
      cache_fetch(cache_key, backend_method: :get_default_branch) do
        self.spokes_api.get_default_branch
      end
    else
      cache_key = repository_reference_cache_key("read_symbolic_ref", "HEAD")
      cache_fetch(cache_key, backend_method: :read_symbolic_ref) do
        self.rpc.read_symbolic_ref("HEAD")
      end
    end
  end

  # This method is used by '/internal/raw/gist' to resolve the gist blob.
  def gist_blob_oid_by_path(path, commit_oid)
    read_tree_entry_oid(commit_oid, path, "blob", :QUALITY_OF_SERVICE_FAIL_FAST)
  end

  # Public: Fetch a single entry in a tree by the path.
  #
  # Returns the 40c OID of the tree entry. If no path is passed, the oid of the
  # root tree is returned. If the path does not exist, raises GitRPC::NoSuchPath.
  # If a type is passed and the object at the path does not match the type,
  # a `GitRPC::InvalidObject` error is raised.
  def read_tree_entry_oid(oid, path = nil, type = nil, qos = nil)
    GitRPC::Util.ensure_valid_full_oid(oid)

    path = GitRPC::Util.normalize_path(path)
    key = "#{path}:#{type}"

    key = content_cache_key("read_tree_entry_oid:v6", oid, sha256(key))
    cache_fetch(key, backend_method: :read_tree_entry_oid) do
      self.spokes_api.read_tree_entry_oid(oid: oid, path: path, type: type, qos: qos)
    end
  end

  def read_blob_oid(commit_oid, path, opts = {})
    if self.feature_enabled?(:read_blob_oid_git)
      self.rpc.read_blob_oid(commit_oid, path, opts.merge(use_git: true))
    else
      science "read_blob_oid_git_experiment" do |e|
        e.context({
          message: :read_blob_oid,
          commit_oid: commit_oid,
          path: path,
          opts: opts,
          repository: self,
        })
        e.run_if { !disable_libgit2_to_git_experiments }
        e.use { self.rpc.read_blob_oid(commit_oid, path, opts.merge(use_git: false)) }
        e.try { self.rpc.read_blob_oid(commit_oid, path, opts.merge(use_git: true)) }
      end
    end
  end

  def read_blob_oids(pairs, skip_bad: false)
    if self.feature_enabled?(:read_blob_oid_git)
      self.rpc.read_blob_oids(pairs, skip_bad:, use_git: true)
    else
      science "read_blob_oid_git_experiment" do |e|
        e.context({
          message: :read_blob_oids,
          pairs: pairs,
          skip_bad: skip_bad,
          repository: self,
        })
        e.run_if { !disable_libgit2_to_git_experiments }
        e.use { self.rpc.read_blob_oids(pairs, skip_bad:, use_git: false) }
        e.try { self.rpc.read_blob_oids(pairs, skip_bad:, use_git: true) }
      end
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
    object_name = object_name.to_s
    if feature_enabled?(:rev_parse_spokes_api) && GitHub.spokesd_enabled?
      self.spokes_api.resolve_object(object_name: object_name)
    else
      science "rev_parse_spokes_api_experiment" do |e|
        e.context({
          object_name: object_name,
          repository: self,
        })
        e.use { self.rpc.rev_parse(object_name) }
        e.try { self.spokes_api.resolve_object(object_name: object_name) }
        e.run_if { !disable_libgit2_to_git_experiments && GitHub.spokesd_enabled? }
      end
    end
  end

  # This is a temporary experiment to safely validate new callers of the SpokesAPI's ResolveObject
  # Once we are confident in the safety of the new callers, we can remove this experiment and the callers will
  # invoke the `rev_parse` method above
  def rev_parse_collection(object_name, use_cache: false)
    run_experiment(:rev_parse_spokes_api_collection, "rev_parse_spokes_api_collection_experiment", object_name, use_cache: use_cache)
  end

  def rev_parse_unsullied_diff(object_name)
    run_experiment(:rev_parse_spokes_api_unsullied_diff, "rev_parse_spokes_api_unsullied_diff_experiment", object_name)
  end

  def rev_parse_comparison(object_name)
    run_experiment(:rev_parse_spokes_api_comparison, "rev_parse_spokes_api_comparison_experiment", object_name)
  end

  def run_experiment(feature_flag_name, experiment_name, object_name, use_cache: true)
    if feature_enabled?(feature_flag_name) && GitHub.spokesd_enabled?
      self.spokes_api.resolve_object(object_name: object_name)
    else
      science experiment_name do |e|
        e.context({
          object_name: object_name,
          repository: self,
        })
        e.use { self.rpc.rev_parse(object_name, use_cache: use_cache) }
        e.try { self.spokes_api.resolve_object(object_name: object_name) }
        e.run_if { !disable_libgit2_to_git_experiments && GitHub.spokesd_enabled? }
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
    GitRPC::Util.ensure_valid_full_oid(commit_oid)

    key = content_cache_key("blame-tree", commit_oid, sha256(root), recursive, "v4")
    cache_fetch(key, backend_method: :blame_tree) do
      begin
        self.spokes_api.blame_tree(commit_oid, root, recursive)
      rescue SpokesAPI::TimedOut
        raise GitRPC::Timeout.new
      end
    end
  end

  def diff_summary_cached?(commit1_oid, commit2_oid, base_commit_oid, algorithm: GitRPC::Client::DIFF_SUMMARY_DEFAULT_ALGORITHM)
    ignore_whitespace = algorithm == GitRPC::Diff::ALGORITHM_IGNORE_WHITESPACE
    key = content_cache_key("read-diff-summary", "v1", commit1_oid, commit2_oid, base_commit_oid, ignore_whitespace)
    self.rpc.diff_summary_cached?(commit1_oid, commit2_oid, base_commit_oid, algorithm: algorithm) ||
      GitHub.cache.exist?(key)
  end

  def read_diff_summary(commit1_oid, commit2_oid, base_commit_oid, commit1_repo: nil, commit2_repo: nil, timeout: GitRPC::Client::DIFF_SUMMARY_TIMEOUT, algorithm: GitRPC::Client::DIFF_SUMMARY_DEFAULT_ALGORITHM)
    ignore_whitespace = algorithm == GitRPC::Diff::ALGORITHM_IGNORE_WHITESPACE
    if GitHub.spokesd_enabled? && self.feature_enabled?(:read_diff_summary_spokes_api)
      self.read_diff_summary_spokes_api(commit1_oid, commit2_oid, base_commit_oid, commit1_repo:, commit2_repo:, timeout:, ignore_whitespace:)
    else
      science "read_diff_summary_spokes_api_experiment" do |e|
        e.context({
          commit1_oid: commit1_oid,
          commit2_oid: commit2_oid,
          commit1_repo: commit1_repo&.id,
          commit2_repo: commit2_repo&.id,
          base_commit_oid: base_commit_oid,
          timeout: timeout,
          algorithm: algorithm,
          repository: self.id,
        })
        e.use { self.rpc.read_diff_summary(commit1_oid, commit2_oid, base_commit_oid, timeout:, algorithm:) }
        e.try { self.read_diff_summary_spokes_api(commit1_oid, commit2_oid, base_commit_oid, commit1_repo:, commit2_repo:, timeout:, ignore_whitespace:) }
        e.run_if { !self.disable_spokes_api_conversions && GitHub.spokesd_enabled? }
        e.ignore do |control, candidate|
          # Our control may not return a too-busy error, but if our candidate
          # does, that's expected (and even desired in some cases).
          #
          # If one side got a timeout and the other didn't, also don't consider
          # that a mismatch.
          candidate&.unavailable_error&.is_a?(SpokesAPI::ResourceExhausted) ||
            control&.unavailable_reason == "timeout" ||
            candidate&.unavailable_reason == "timeout"
        end
      end
    end
  end

  def read_diff_summary_spokes_api(commit1_oid, commit2_oid, base_commit_oid, commit1_repo: nil, commit2_repo: nil, timeout: GitRPC::Client::DIFF_SUMMARY_TIMEOUT, ignore_whitespace: false)
    GitRPC::Util.ensure_valid_full_oid(commit2_oid)
    GitRPC::Util.ensure_valid_full_oid(commit1_oid) if commit1_oid
    GitRPC::Util.ensure_valid_full_oid(base_commit_oid) if base_commit_oid

    timeout_key = content_cache_key("read-diff-summary", "v1", commit1_oid, commit2_oid, base_commit_oid, ignore_whitespace, "timed-out")
    previous_timeout = GitHub.cache.fetch(timeout_key) { nil }

    if previous_timeout && timeout <= previous_timeout
      return GitRPC::Diff::Summary.unavailable(reason: "timeout", error: nil)
    end

    key = content_cache_key("read-diff-summary", "v1", commit1_oid, commit2_oid, base_commit_oid, ignore_whitespace)
    client = self.spokes_api(timeout: timeout)
    begin
      data = cache_fetch(key, backend_method: :read_diff_summary) do
        client.read_diff_summary(commit1_oid:, commit2_oid:, base_commit_oid:, commit1_repo:, commit2_repo:, with_stats: true, ignore_whitespace:)
      end
      null_oid = nil
      deltas = data[:deltas].take(GitRPC::Diff::DiffTreeParser::MAX_FILES).flat_map do |d|
        if d[:status] == "T"
          null_oid ||= d[:old_file][:oid].gsub(/[0-9a-f]/, "0")
          # gitrpcd doesn't split these changes, but GitRPC does.  Split them
          # here to prevent mismatches.
          [
            GitRPC::Diff::Summary::Delta.new(
              old_file: d[:old_file],
              new_file: {
                oid: null_oid, mode: GitRPC::NULL_MODE,
                path: d[:old_file][:path],
              },
              additions: d[:deletions].nil? ? nil : 0,
              deletions: d[:deletions],
              status: "D", similarity: 0,
            ),
            GitRPC::Diff::Summary::Delta.new(
              old_file: {
                oid: null_oid, mode: GitRPC::NULL_MODE,
                path: d[:new_file][:path],
              },
              additions: d[:additions],
              deletions: d[:additions].nil? ? nil : 0,
              new_file: d[:new_file],
              status: "A", similarity: 0,
            ),
          ]
        else
          [GitRPC::Diff::Summary::Delta.new(**d)]
        end
      end
      GitRPC::Diff::Summary.new(deltas: deltas, **data.slice(:additions, :deletions, :changed_files))
    rescue SpokesAPI::TimedOut => boom
      GitHub.cache.set(timeout_key, timeout)
      GitRPC::Diff::Summary.unavailable(reason: "timeout", error: boom)
    rescue SpokesAPI::NotFound => boom
      if boom.to_s.start_with? "object not found"
        GitRPC::Diff::Summary.unavailable(reason: "missing commits", error: boom)
      else
        # Missing repository.
        GitRPC::Diff::Summary.unavailable(reason: "corrupt", error: boom)
      end
    rescue SpokesAPI::ResourceExhausted => boom
      GitRPC::Diff::Summary.unavailable(reason: "too busy", error: boom)
    rescue SpokesAPI::Error => boom
      GitRPC::Diff::Summary.unavailable(reason: "corrupt", error: boom)
    end
  end

  def read_latest_wiki_pages(oid)
    if !GitRPC::Util.valid_full_oid?(oid)
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

  def resolve_references(refnames, source:)
    cache_in_spokes_adapter = self.feature_enabled?(:resolve_references_cache_spokes_adapter)

    resolve_references_internal(refnames, do_cache: cache_in_spokes_adapter) do |filtered_refnames|
      if self.id && GitHub.spokesd_enabled? && cache_in_spokes_adapter && self.feature_enabled?("resolve_references_spokes_#{source}")
        filtered_refnames.each_slice(SpokesAPI::Client::resolve_references_ref_limit).flat_map do |batch|
          self.spokes_api.resolve_references(batch)
        end
      else
        large_request = (filtered_refnames.size > 1000)
        context = {
          repository: self.id,
          ref_count: filtered_refnames.size
        }
        context[:refnames] = filtered_refnames unless large_request
        science "resolve_references_spokes_#{source}" do |e|
          e.context(context)
          e.use { self.rpc.read_qualified_refs(filtered_refnames, do_cache: !cache_in_spokes_adapter) }
          e.try do
            filtered_refnames.each_slice(SpokesAPI::Client::resolve_references_ref_limit).flat_map do |batch|
              self.spokes_api.resolve_references(batch)
            end
          end
          e.compare_errors do |control, candidate|
            # When requests are made to this endpoint on a repository that has not
            # been created on disk, GitRPC triggers a UnroutedError (or one of its subclasses) or
            # InvalidRepository and the Spokes API triggers SpokesAPI::NotFound.
            # Treat these errors as equivalent.
            if ((control.is_a? GitHub::DGit::UnroutedError) && (candidate.is_a? SpokesAPI::NotFound)) ||
              ((control.is_a? GitRPC::InvalidRepository) && (candidate.is_a? SpokesAPI::NotFound))
              true
            elsif (control.is_a? GitRPC::Timeout) && (candidate.is_a? SpokesAPI::TimedOut)
              # GitRPC & Spokes API timeout errors are equivalent
              true
            else
              control.class == candidate.class && control.message == candidate.message
            end
          end
          e.clean do |value|
            if large_request
              { ref_count: value.size, truncated_result: value[0..1000] }
            else
              value
            end
          end
          e.run_if { self.id && GitHub.spokesd_enabled? }
        end
      end
    end
  end

  private def resolve_references_internal(refnames, do_cache:)
    # If we're not caching here, just execute the block
    return yield refnames unless do_cache

    refname_to_cache_key = refnames.map do |refname|
      [refname, repository_reference_cache_key("resolve_references", "v1", Digest::SHA256.hexdigest(refname))]
    end.to_h

    cached_refs = {}
    missing_refnames = []

    target_oids_from_cache = cache_get_multi(refname_to_cache_key.values, backend_method: :resolve_references)
    refnames.each do |refname|
      cache_key = refname_to_cache_key[refname]
      if target_oids_from_cache.has_key?(cache_key)
        cached_refs[refname] = target_oids_from_cache[cache_key]
      else
        missing_refnames << refname
      end
    end

    if missing_refnames.any?
      missing_refnames.zip(yield missing_refnames) do |refname, result|
        target_oid = result[1]
        cached_refs[refname] = target_oid
        GitHub.cache.set(refname_to_cache_key[refname], target_oid) if do_cache
      end
    end

    refnames.zip(cached_refs.values_at(*refnames))
  end

  private

  # Internal: run and instrument GitHub.cache.get_multi
  def cache_get_multi(keys, backend_method:)
    GitHub.instrument("cache_get_multi.spokes_adapter", backend_method: backend_method, keys: keys) do |instrument_payload|
      results = GitHub.cache.get_multi(keys)
      instrument_payload[:results] = results
      results
    end
  end

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
