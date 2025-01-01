# typed: true
# frozen_string_literal: true

# Calculates and maintains a cache of the last commit to touch tree entries in a
# repository. This is displayed for each file on tree pages and also in the
# commit tease portion of tree and blob pages.
#
# Determining the last commit to touch a path in git is an expensive operation.
# It requires walking the commit history graph and for each commit comparing the
# before and after trees for modifications to the given entry.
class TreeHistory
  attr_reader :repository
  attr_reader :commit_oid
  attr_reader :root
  attr_reader :tree_entries

  # Maximum number of entries that may be in a tree. When there's more entries
  # than this, no history information is loaded for the entries.
  MAX_TREE_SIZE = 7000

  # Sentinel value that gets cached when a timeout occurs to avoid repeating
  # requests for timeouts over and over.
  TIMEOUT_SENTINEL = :_timeout

  # Create a new TreeHistory.
  #
  # repository - The Repository object whose git data we're analyzing.
  # commit_oid - The commit oid string where history searching starts.
  # root       - The path to the containing tree for the entries to retrieve
  #              information on. Blank for root tree entries. Note that this
  #              isn't the path to the tree entry to retrieve history for but
  #              its container.
  # entries    - The Array of entries.
  # truncated_entries_count - The number of entries truncated and thus not available
  #                           in entries for this tree history. Truncation
  #                           happens in the web UI and other places for
  #                           directories that are too large to show in full.
  def initialize(repository, commit_oid, root = "", entries = nil, truncated_entries_count = nil)
    raise ArgumentError, "nil root path is invalid" if root.nil?
    raise ArgumentError, "entries are required" if entries.nil?
    @repository = repository
    @commit_oid = commit_oid
    @root = root
    @tree_entries = entries
    @tree_entries_length = @tree_entries.length + (truncated_entries_count || 0)
  end

  # Public: The commit where history searching will start when all entries are
  # not available in cache.
  #
  # Returns a Commit object for the commit_oid given in the contstructor.
  def commit
    @commit ||= repository.commits.find(commit_oid)
  end

  # Public: Loads the most recent commit for a single tree entry under the
  # given root path. Attempts to find it in memcached, falls back to fileservers
  # if it cannot be found.
  #
  # This method should only be used when loading a single tree entry's
  # last commit information and not when many tree entries's information is
  # needed. Use the batch method load_cached_entries() to read last commit
  # information for all entries under the root path's tree.
  #
  # entry_name - The string name of the tree entry relative to the root path
  #              given in the initializer. Only immediate child entries may
  #              be specified.
  #
  # Returns a Commit object or nil when no history could be established for
  # the tree entry given.
  def load_or_calculate_single_entry(entry_name)
    entry = tree_entries.find { |ent| ent.name == entry_name }

    # Bail with no matching tree entry
    return nil if entry.nil?

    # Try to find the tree entry's last commit in cache or fallback to
    # performing a single rev-list command.
    key = tree_entry_commit_key(entry.path)

    commit_oid = begin
      cache.fetch(key) do
        repository.revision_list(self.commit_oid, 1, 0, entry.path).first
      end
    rescue GitRPC::Timeout
      ttl = 4.minutes + rand(1.minute.to_i)
      cache.set(key, TIMEOUT_SENTINEL, ttl)
      TIMEOUT_SENTINEL
    end

    if commit_oid == TIMEOUT_SENTINEL
      raise GitRPC::Timeout
    end

    # Don't attempt to load commit if it doesn't exist.
    #
    # NULL_OID means that blame-tree returned incomplete information. We don't
    # want to continually try to load bad data, so we cache the failure.
    if commit_oid && commit_oid != GitRPC::NULL_OID
      repository.commits.find(commit_oid)
    end
  end

  # Public: Load last touched commit information from cache for all entries in
  # the given root tree. This is typically used when you need history
  # information for all items in a tree as opposed to a single specific path.
  #
  # Returns a hash of { path => Commit } items. Only already cached entries
  # are included. Anything not in cache is not present in the hash.
  def load_all_cached_entries
    return {} if over_max_tree_size?

    # grab <path> => <commit oid> mappings for everything in cache
    entry_commit_oids = cached_entry_commit_oids

    # grab all commits and build an oid => commit object map
    commit_oids = entry_commit_oids.values.compact.uniq
    commit_oids.reject! { |oid|  oid.starts_with?("^") || oid == GitRPC::NULL_OID }  # reject boundary commits
    commits = repository.commits.find(commit_oids).index_by(&:oid)

    # associate each tree entry with a real commit object
    entry_commit_oids.inject({}) do |hash, (path, commit_oid)|
      if commit_oid == GitRPC::NULL_OID
        hash[path] = Directory::NilCommit.new
      elsif commit_oid.nil? || commits[commit_oid].nil?
        # NOOP
      else
        hash[path] = commits[commit_oid]
      end
      hash
    end
  rescue GitRPC::ObjectMissing
    # A commit that previously existed has been gc'd. Force a rebuild of the
    # history by clearing the cache out and returning an empty hash.
    clear_cached_entry_commit_oids
    {}
  end

  # Public: Calculate the last commit to touch each entry under the given
  # root path, write to cache, and then return all entries in the same way
  # as load_all_cached_entries.
  #
  # The big difference between this method and load_all_cached_entries is that
  # this method will go to the fs machine and actually perform the last touched
  # calculation whereas load_all_cached_entries only loads from cache.
  #
  # Returns a hash of { path => Commit } items. All entries should be
  # present and no Commit object should be nil. Returns an empty hash when the
  # number of tree entries exceeds MAX_TREE_SIZE.
  def calculate_all_entries
    return {} if over_max_tree_size?

    # figure out what we already have cached and what's missing
    cached_oids = cached_entry_commit_oids
    missing = tree_entries.select do |entry|
      cached_oids[entry.path].nil? || cached_oids[entry.path] == GitRPC::NULL_OID
    end
    missing = missing.index_by(&:path)

    # if we have everything in cache, bail out now
    if missing.empty?
      entries = load_all_cached_entries
      return entries if entries.size > 0
    end

    # map entry full paths to entry objects so we can reassociate things
    pathmap = tree_entries.index_by { |entry| entry.path }

    # make the remote call to get a list of all tree entries with their last
    # modifying commit oid
    blame_tree.each do |commit_oid, path|
      next if commit_oid.starts_with?("^")  # skip boundary commits
      missing.delete(path)

      if entry = pathmap[path]
        if cached_oids[entry.path] != commit_oid
          key = tree_entry_commit_key(entry.path)
          cache.set(key, commit_oid)
        end
        cached_oids[entry.path] = commit_oid
      else
        GitHub.logger.warn(
          "Tree entry missing",
          "code.namespace" => self.class.name,
          "code.function" => "calculate_all_entries",
          "gh.repo.id" => repository.id,
          "git.commit.oid" => commit_oid,
          "gh.repo.root" => root,
          "gh.repo.path" => path
        )
      end
    end

    missing.each do |path, _entry|
      cache.set(tree_entry_commit_key(path), GitRPC::NULL_OID, 1.minute)
    end

    # now that we have commit oids for all tree entries, use the normal cached
    # commit loading to build the { name => oid } map.
    load_all_cached_entries
  end

  def over_max_tree_size?
    @tree_entries_length > MAX_TREE_SIZE
  end

  class TreeHistoryError < StandardError; end

  # Internal: Run the git-blame-tree command via RPC and parse its output.
  # Each line of output is a "<oid> <path>" where <oid> is the commit that
  # last touched the tree entry at <path>.
  #
  # Note: not passing an empty string as root cuts load time in half on
  # large repositories, see https://github.com/github/github/pull/15782
  #
  # Returns an array of [oid, path] elements. There should be one item per tree
  # entry. The path is the full path to the tree entry from the root tree.
  def blame_tree
    repository.blame_tree(commit_oid, root, false).map { |path, oid| [oid, path] }
  rescue GitRPC::CommandBusy, GitRPC::Timeout => e
    meta = {
      :exception => e,
      "code.namespace" => self.class.name,
      "code.function" => "blame_tree"
    }
    if e.respond_to?(:argv)
      meta["process.command_args"] = T.unsafe(e).argv
    end
    GitHub.logger.error(meta)
    @too_busy = true
    []
  rescue GitRPC::SpawnFailure => e
    unless e.original.is_a? GitRPC::Timer::Error
      GitHub.logger.error(
        :exception => e,
        "code.namespace" => self.class.name,
        "code.function" => "blame_tree"
      )
      raise TreeHistoryError.new
    end
    @too_busy = true
    []
  end

  def too_busy?
    !!@too_busy
  end

  # Internal: Load from cache all commit oids that last modified each of the tree
  # entries under the TreeHistory's root path. This does not calculate any history
  # that isn't already in cache.
  #
  # Returns a hash of { path => commit_oid } mappings. When last commit
  # info for an entry was not present in cache, the commit_oid will be nil.
  def cached_entry_commit_oids
    @cached_entry_commit_oids ||= cached_entry_commit_oids!
  end

  # Internal: Actually load the commit oids from cache. This is memoized so that
  # calculate_all_entries can update an already loaded cached list in place
  # which avoids having to do a separate roundtrip to memcached after
  # calculating missing entries.
  def cached_entry_commit_oids!
    keymap = cached_entry_keymap
    commit_oids = cache.get_multi(keymap.keys)
    commit_oids.reject! { |_key, value| value == TIMEOUT_SENTINEL }

    keymap.inject({}) do |hash, (key, entry)|
      hash[entry.path] = commit_oids[key]
      hash
    end
  end

  # Internal: Clear all cached entries from cache. This is used when a commit
  # referenced from the cache no longer exists in the repository. When this
  # happens, we need to rescan the history to find the new commits.
  def clear_cached_entry_commit_oids
    cached_entry_keymap.each_key do |key|
      cache.delete(key)
    end
  end

  # Internal: Hash of memcached key to tree entries for each item in the tree.
  def cached_entry_keymap
    keymap = {}
    tree_entries.each do |entry|
      key = tree_entry_commit_key(entry.path)
      keymap[key] = entry
    end
    keymap
  end

  # Internal: Tree entry last modifying commit cache key. This is the last commit
  # to modify a path that has the given tree entry.
  #
  # path  - full path to the tree entry.
  #
  # Returns the cache key.
  def tree_entry_commit_key(path)
    "tree-commits:v7:#{repository.repository_cache_key}:#{commit_oid}:#{Digest::SHA256.hexdigest(path.to_s)}"
  end

  # Internal: The memcached interface.
  def cache
    GitHub.cache
  end
end
