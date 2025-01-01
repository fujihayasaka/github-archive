# typed: true
# frozen_string_literal: true

# Responsible for the collection of files and other directories at a given
# commit or ref starting at a path from root.
#
# This is sometimes called a tree, but is specifically named directory as to
# not conflate with Git Trees. Similar, but different terms.
class Directory
  include FailbotHelper
  include Enumerable

  attr_reader :commitish, :path, :repository

  # repository - Repository for the Directory we want.
  # commitish  - A ref or commit String mapping to the snapshot we want.
  # path       - The path String from the root of the repository.
  def initialize(repository, commitish, path)
    @commitish = commitish
    @commit_sha = repository.ref_to_sha(commitish)
    @path = path.blank? ? nil : path
    @repository = repository
  end

  def load_tree_entries!
    @tree_oid, @tree_entries, @truncated_entries = repository.tree_entries(commit_sha, path, needs_truncated_count: true)
  end

  # The Git Tree object's contents that represents this particular Directory.
  #
  # Returns an Array of Blobs, Trees, and Submodules.
  def tree_entries
    return @tree_entries if defined?(@tree_entries)
    load_tree_entries!
    @tree_entries
  end

  def tree_oid
    return @tree_oid if defined?(@tree_oid)
    load_tree_entries!
    @tree_oid
  end

  def truncated_entries
    return @truncated_entries if defined?(@truncated_entries)
    load_tree_entries!
    @truncated_entries
  end

  def total_count
    return tree_entries.size unless truncated?
    truncated_entries + tree_entries.size
  end

  def truncated?
    truncated_entries.present?
  end

  # Public: The preferred README file from within the current Directory.
  #
  # Returns a TreeEntry or nil.
  def preferred_readme
    return @preferred_readme if defined?(@preferred_readme)
    @preferred_readme = PreferredFile.find(directory: self, type: :readme)
  rescue GitRPC::ObjectMissing
    nil
  end

  # Is there a readme at this directory?
  #
  # Returns a boolean.
  def has_readme?
    preferred_readme.present?
  rescue => e # rubocop:todo Lint/RescueException
    failbot e
    false
  end

  # Supports all of the Enumerable methods.
  #
  # Returns nothing.
  def each(&block)
    items.each do |item|
      yield item
    end
  end

  def simplify_paths
    @tree_oid, @tree_entries, @truncated_entries = repository.tree_entries(commit_sha, path, simplify_paths: true, needs_truncated_count: true)
  end

  # Internal: Directories and Files with their history that exist at this
  # Directory level. Sorts such that Directories are on top and excludes items
  # without a name.
  #
  # If the TreeHistory is in cache, it is attached to each item. If it is not,
  # a nil history is attached. Partial histories can also be attached here.
  #
  # Returns an Array of Trees, Blobs, and Submodules.
  def items
    return @items if @items
    return [] unless tree_entries # Will be nil if path is not actually a tree

    # Sort entries into the proper order.
    @items = tree_entries.partition { |t| %w[tree commit].include?(t.type) }.
                             flatten.
                             select { |t| !t.name.blank? }

    @history_cached = T.let(true, T.nilable(T::Boolean))
    cached_history = tree_history.load_all_cached_entries

    @items = @items.collect do |item|
      result = { content: item, name: item[:name] }
      if commit = cached_history[item.path]
        result[:age] = commit.date
        result[:commit] = commit
      else
        @history_cached = false
        result[:age] = nil
        result[:commit] = NilCommit.new
      end
      result
    end

    # If the server was too busy to generate proper blame-tree
    # information, then NilCommits are the best we're going to get for
    # now.  Avoid setting @history_cached to false, or we get a
    # request loop that persists until the server gets un-busy.
    @history_cached ||= tree_history.too_busy?

    @items
  end

  # A simple empty commit class to pass on. This should really be an app-level
  # thing that Commit supports.
  class NilCommit
    attr_reader :message, :date
  end

  # Public: Is the history for this Tree fully in cache?
  def history_cached?
    items
    @history_cached
  end

  # Public: Can we compute the history of this directory. In order to show the
  # entries for this directory with their last commit, we need to perform a
  # blame-tree on the directory (in tree_history). This blame-tree is too
  # expensive for directories with a lot of entries, so tree_history noops the
  # history calculation if the directory is over the max tree size.
  def can_compute_history?
    !tree_history.over_max_tree_size?
  end

  # Internal: The TreeHistory object for this Directory.
  #
  # Returns a TreeHistory object.
  def tree_history
    @tree_history ||= TreeHistory.new(repository, commit_sha, path.nil? ? "" : path, tree_entries, @truncated_entries)
  end

  def ==(other)
    self.class == other.class &&
      tree_oid == other.tree_oid
  end

  # The contents of the tree

  # The String commit SHA1 of the commitish.
  attr_reader :commit_sha
end
