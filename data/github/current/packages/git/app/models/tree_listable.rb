# typed: true
# frozen_string_literal: true

# Methods related to reading git trees and tree entries.
# This mostly deals with listing Tree and Blob objects objects.
module TreeListable
  extend T::Helpers
  requires_ancestor { GH::Interfaces::GitRPC }
  requires_ancestor { GH::Interfaces::DefaultBranch }
  requires_ancestor { GitRepository::SpokesAdapter }

  DEFAULT_LIMITS = { truncate: false, limit: 1.megabytes }

  # Fetch the tree entries for a tree referenced by a commitish and a path
  #
  # treeish - A string referencing either a commit sha or a tree sha.
  # path    - The path of the subtree to retrieve entries from.
  #
  # Returns three-element tuple with String tree oid, Array of tree entries, and
  # Boolean value for whether entries were truncated
  def tree_entries(treeish, path, recursive: false, limit: 1000, simplify_paths: false, skip_size: true)
    result = if recursive
      rpc.read_tree_entries_recursive(treeish, path, limit)
    else
      rpc.read_tree_entries(treeish, path: path, limit: limit, simplify_paths: simplify_paths, skip_size: skip_size)
    end

    entries = result["entries"].map do |tree_entry|
      tree_entry["collection"] = true
      TreeEntry.new(self, tree_entry)
    end

    [result["oid"], entries, result["truncated_entries"]]
  end

  # Fetch a single TreeEntry from a path and a commit or tree
  #
  # oid  - A string referencing either a commit sha or a tree sha.
  # path - The path of the entry to fetch.
  #
  # Returns a TreeEntry
  # Raises GitRPC::NoSuchPath if no tree entry is found
  def tree_entry(oid, path, opts = {})
    opts = DEFAULT_LIMITS.merge(opts)
    TreeEntry.new(self, rpc.read_tree_entry(oid, path, opts))
  end

  # Fetch a blob by path at a commit
  #
  # Delegates to tree entry, but does some error handling if the TreeEntry
  # is not a blob.
  #
  # oid  - The oid of either a tree object or a commit object to search in
  # path - The path to find relative to the root tree
  #
  # Returns a TreeEntry (guaranteed to be a blob type)
  # Returns nil if no blob is found
  def blob(oid, path, limits = DEFAULT_LIMITS)
    tree_entry(oid, path, limits.merge(type: "blob"))
  rescue GitRPC::NoSuchPath
    nil
  end

  # Fetch a tree by path at a commit
  #
  # Delegates to tree entry, but does some error handling if the TreeEntry
  # is not a tree.
  #
  # oid  - The oid of either a tree object or a commit object to search in
  # path - The path to find relative to the root tree
  #
  # Returns a TreeEntry (guaranteed to be a tree type)
  # Returns nil if no tree is found
  def tree(oid, path)
    tree_entry(oid, path, type: "tree")
  rescue GitRPC::NoSuchPath
    nil
  end

  # Fetch a blob by oid
  #
  # oid - The oid of the blob to fetch
  #
  # Returns a Blob object
  def blob_by_oid(oid, full_blob: true)
    blob_hash = if full_blob
      rpc.read_full_blob(oid)
    else
      self.read_objects([oid], :blob).first
    end

    Blob.new(self, blob_hash)
  end

  # Fetch all blobs for referenced by a commitish and a path
  #
  # treeish - A string referencing either a commit sha or a tree sha.
  def blobs(treeish)
    tree_summary = rpc.read_tree_summary_recursive(treeish)
    tree_summary.map do |tree_entry|
      tree_entry["type"] = "blob"
      data = tree_entry.delete("content")
      tree_entry["data"] = data if data
      TreeEntry.new(self, tree_entry)
    end
  end

  # Create a Directory object for a specified oid and path.
  #
  # oid  - A String referencing either a commit sha or a tree sha
  # path - The path to the directory to retrieve. Defaults to the root directory.
  #
  # Returns a Directory object
  def directory(oid, path = nil)
    Directory.new(self, oid, path).tap do |dir|
      return nil unless dir.commit_sha
    end
  rescue GitHub::DGit::UnroutedError
    nil
  end

  # Create a Directory object at an oid and the root path.
  #
  # oid - A String referencing either a commit sha or a tree sha,
  #       defaults to the base branch. (Default: default_branch)
  #
  # Returns a Directory object
  def root_directory(ref: default_branch)
    directory(ref)
  end
end
