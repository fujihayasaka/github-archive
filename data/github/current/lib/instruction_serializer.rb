# typed: false
# frozen_string_literal: true

module InstructionSerializer
  class Graph
    attr_reader :nodes

    def initialize
      @nodes = []
    end

    def add_node(node)
      @nodes.push(node)
    end

    def has_dependency_cycles?
      @nodes.each do |node|
        visited = { node.name => true }
        if has_dependency_cycle?(node, visited)
          return true
        end
      end

      false
    end

    private

    def has_dependency_cycle?(node, visited)
      if node.before.length == 0
        return false
      end

      node.before.each do |before_node|
        if visited[before_node.name]
          puts node.name
          puts before_node.name
          return true
        else
          visited[before_node.name] = true
          return has_dependency_cycle?(before_node, visited)
        end
      end
    end
  end

  class Node
    attr_reader :before, :kind, :name, :next, :tables
    attr_accessor :parent

    def initialize(name, kind)
      @before = []
      @kind = kind
      @name = name
      @next = []
      @parent = nil
      @tables = []
    end

    def add_before(node)
      @before.push(node)
    end

    def add_next(node)
      @next.push(node)
    end

    def add_table(table)
      @tables.push(table)
    end
  end

  class Tree
    attr_accessor :root

    def from_graph(g)
      # Connect all nodes without any dependencies to the root.
      g.nodes.each do |node|
        if node.before.length == 0
          node.add_before(@root)
          @root.add_next(node)
        end
      end

      # Add the root node to the graph.
      g.add_node(@root)

      # Prune routes from root -> node.
      prune_shorter_routes_from_node(@root)
    end

    def initialize
      @root = Node.new("root", "meta")
    end

    def height(node)
      if node.nil?
        return 0
      end

      max_child_height = 0
      node.next.each do |child|
        child_height = height(child)
        max_child_height = [max_child_height, child_height].max
      end

      max_child_height + 1
    end

    def print_current_level(node, level)
      if node.nil?
        return
      end

      if level == 1
        $stdout.write("%s " % [node.name])
      elsif level > 1
        node.next.each do |child|
          print_current_level(child, level - 1)
        end
      end
    end

    def print_level_order
      height = self.height(@root)
      (1..height).each do |level|
        print_current_level(@root, level)
        $stdout.write("\n\n")
      end
    end

    def serialize
      nodes = []
      (1..self.height(@root)).each do |level|
        nodes.concat(get_nodes_in_level(@root, level))
      end

      nodes
    end

    def get_nodes_in_level(node, level)
      return [] if node.nil?

      if level == 1
        return [{
                  children: node.next.map { |child| child.name },
                  dependencies: node.before.map { |dep| dep.name },
                  id: node.name,
                  kind: node.kind,
                }]
      end

      child_nodes = []
      node.next.each do |child|
        child_nodes.concat(get_nodes_in_level(child, level - 1))
      end

      child_nodes
    end

    private

    def depth_of_node(node, num_hops)
      # Exit condition: Node with no parents is the root.
      if node.before.length == 0
        return num_hops
      end

      max_hops = 0
      node.before.each do |parent|
        max_hops = [max_hops, depth_of_node(parent, num_hops + 1)].max
      end

      max_hops
    end

    def prune_shorter_routes_from_node(node)
      if node.before.length >= 1
        max_hops = 0
        parent_node = nil

        # Figure out the parent with the longest path to root. This is
        # the "real" parent.
        node.before.each do |parent|
          parent_hops = depth_of_node(parent, 1)
          if parent_hops > max_hops
            max_hops = parent_hops
            parent_node = parent
          end
        end
        node.parent = parent_node

        # Remove the current node as a child of all the other parents.
        node.before.each do |parent|
          parent.next.delete(node) unless parent == node.parent
        end
      end

      if node.next.length > 0
        node.next.dup.each do |child|
          prune_shorter_routes_from_node(child)
        end
      end
    end
  end

  def self.generate_migration_batch(node, level, processed_nodes, carry_over)
    return [] if node.nil?

    if level == 1
      node.before.each do |dep|
        if !processed_nodes.has_key?(dep.name)
          $stdout.write("%s has unresolved dependencies. skipping. \n" % dep.name)
          return []
        end
      end
      processed_nodes[node.name] = true
      return [node.name]
    end

    sub_batch = []
    node.next.each do |child|
      sub_batch.concat(generate_migration_batch(child, level - 1, processed_nodes, carry_over))
    end

    sub_batch
  end

  def self.build_migration_instructions(metadata_json)
    g = Graph.new
    id_to_node = {}
    table_to_nodes = {}

    migrations = metadata_json["migrations"]

    migrations.each do |migration|
      id = migration["migration_id"]
      kind = migration["type"]

      if id_to_node[id].nil?
        node = Node.new(id, kind)
        id_to_node[id] = node
        g.add_node(node)
      else
        node = id_to_node[id]
      end

      migration["table_names"].each do |table_name|
        node.add_table(table_name)

        table_to_nodes[table_name] = [] if table_to_nodes[table_name].nil?
        table_to_nodes[table_name].push(node)
      end
    end

    # For each table bidirectionally link the nodes together.
    # The Array#include? calls here are painful. Do something about that later.
    table_to_nodes.each do |_, nodes|
      nodes.each_with_index do |node, index|
        before_idx = index - 1
        next_idx = index + 1

        if before_idx >= 0
          node.add_before(nodes[before_idx]) unless node.before.include?(nodes[before_idx])
        end

        if next_idx < nodes.length
          node.add_next(nodes[next_idx]) unless node.next.include?(nodes[next_idx])
        end
      end
    end

    # If the graph has dependency cycles: halt.
    if g.has_dependency_cycles?
      $stdout.write("dependency cycles detected in Graph\n")
      return false
    end

    # Create a Tree from the Graph.
    t = Tree.new
    t.from_graph(g)
    t.serialize
  end
end
