# typed: true
# frozen_string_literal: true

class GitHub::Diff::Tree
  # Constructs a tree data structure of changed files in the given diff,
  # sorted by path name
  #
  # diff - an instance of GitHub::Diff
  # flatten_fileless_directories - Boolean
  #
  # Returns a GitHub::Diff::TreeNode
  def self.build(diff, flatten_fileless_directories:)
    tree_depth = 0
    root = GitHub::Diff::TreeNode.new(tree_depth: tree_depth)
    deltas = diff.summary.deltas.sort_by { |delta| delta.path.to_s }

    deltas.each do |delta|
      *path_segments, filename = delta.path.split("/")
      root.add_node(path_segments, filename, delta, tree_depth + 1)
    end

    if flatten_fileless_directories
      flatten(root)
    else
      root
    end
  end

  private_class_method def self.flatten(root)
    visit(root) do |node|
      if should_collapse?(node)
        only_child = node.children.first
        node.reparent(only_child)
        true # Return true to signal node needs revisiting
      else
        node.reinsert
        false
      end
    end

    root
  end

  private_class_method def self.should_collapse?(node)
    node.directory? && node.children.count == 1 && node.children.first.directory?
  end

  private_class_method def self.visit(node)
    queue = []
    queue.unshift(*node.children)

    until queue.empty?
      current_node = queue.shift
      should_revisit = yield current_node
      queue.unshift(current_node) and next if should_revisit

      if current_node.directory?
        queue.unshift(*current_node.children)
      end
    end
  end
end

class GitHub::Diff::TreeNode
  attr_reader :delta, :name
  attr_accessor :nodes, :tree_depth, :parent

  # Constructs a tree node object with optional parent and children relationships.
  #
  # name (optional) - binary String path name
  # parent (optional) - an instance of GitHub::Diff::TreeNode
  # is_directory (optional) - Boolean for whether node is a directory
  # delta (optional) - an instance of GitRPC::Diff::Summary::Delta
  # tree_depth - Integer, zero indexed position in the tree
  #
  def initialize(name: ".", parent: nil, is_directory: true, delta: nil, tree_depth:)
    @name = name
    @parent = parent
    @is_directory = is_directory
    @delta = delta
    @nodes = {}
    @tree_depth = tree_depth
  end

  # Inserts a node into the tree
  #
  # path_segments - Array of binary Strings representing each part of the full file path
  # filename - binary String filename
  # delta - an instance of GitRPC::Diff::Summary::Delta
  # tree_depth - Integer, zero indexed position in the tree
  #
  # Returns Hash of nodes after recursing through each node in the given path segments
  def add_node(path_segments, filename, delta, tree_depth)
    # Adjust by 1 because tree depth is zero indexed
    if (tree_depth - 1) == path_segments.length
      node = self.class.new(
        name: filename,
        parent: self,
        is_directory: false,
        delta: delta,
        tree_depth: tree_depth
      )
      @nodes[filename] = node
    else
      next_segment = path_segments[tree_depth - 1]
      next_parent = nodes[next_segment] ||= self.class.new(
        name: next_segment,
        parent: self,
        tree_depth: tree_depth
      )
      next_parent.add_node(path_segments, filename, delta, tree_depth + 1)
    end
  end

  def directory?
    @is_directory
  end

  def children
    nodes.values
  end

  # Retrieves direct child node by name. Primarily for use in tests.
  #
  # name - String, will be converted to binary encoding if not already
  #
  # Returns Diff::TreeNode or nil
  def find_child_by_name(name)
    nodes[name.b]
  end

  def reparent(child)
    old_name = name
    new_name = "#{old_name}/#{child.name}"

    self.name = new_name
    self.parent.nodes[new_name] = self
    self.nodes = child.nodes
    child.nodes.each do |_name, child_node|
      child_node.parent = self
    end
    self.parent.nodes.delete(old_name)
    child.tree_depth -= 1
  end

  def reinsert
    self.parent.nodes.delete(name)
    self.parent.nodes[name] = self
    self.tree_depth = parent.tree_depth + 1
  end

  delegate :path, :deleted?, :submodule?, :symlink?, :status_label, to: :delta, allow_nil: true

  private

  attr_writer :name
end
