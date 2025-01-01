# typed: true
# frozen_string_literal: true

module Arvore
  class ParentNotFound < StandardError; end
  class InvalidWildcard < StandardError; end

  # Class that represents a node on a saved tree.
  # The tree structure is saved in as a enumerated path
  # in one column on the database.
  class Node
    DEFAULT_DELIMITER = "/"

    class_attribute :node_model

    # Initialize a node with the enumerated path.
    #
    # path: Encoded enumerated path. Probably coming directly from the database
    def initialize(path)
      @node_path = path
    end

    # Returns the path set on creation
    def path
      @node_path
    end

    # Returns a new selected node with a shared lock on it.
    # This is used when we need to add a new node under a parent node
    # Therefor, we need to lock the parent node, to make sure it won't
    # move or being removed.
    def self.node_with_lock(id)
      return new("") unless id
      sql = Arel.sql(<<-SQL, node_id: id)
        SELECT tree_path
        FROM `#{node_model.table_name}`
        WHERE `#{node_model.table_name}`.id = :node_id
        LIMIT 1
        LOCK IN SHARE MODE
      SQL
      if parent_tree_path = node_model.connection.select_value(sql)
        new(parent_tree_path)
      else
        nil
      end
    end

    # Create a new node on the tree, creating a new record in the DB for it
    #
    # id: The id to be used on the path
    # parent_id: if given, the node will be created under that parent.
    #
    # Returns a new TeamTreeNode encapsulating the tree path after being created
    def self.create(id, parent_id = nil)
      parent = node_with_lock(parent_id)
      raise ParentNotFound, "Parent node[#{parent_id}] not found." unless parent
      parent.insert(id)
    end

    # Moves the current node to a new parent
    #
    # parent_id: The new parent_id this node will be moved to. If parent_id is nil
    #            it will move this to a root level.
    #
    # Returns a new TeamTreeNode encapsulating the tree path after being moved
    def move_to(parent_id)
      parent_node = self.class.node_with_lock(parent_id)
      raise ParentNotFound, "Parent node[#{parent_id}] not found." unless parent_node
      new_parent_path = new_path_string(parent_node.path)

      self_id = new_path_string(@node_path).id
      new_tree_path = new_parent_path.append(self_id)

      self.class.node_model.connection.update(Arel.sql(<<-SQL, old_path: @node_path, new_path: new_tree_path))
        UPDATE `#{self.class.node_model.table_name}`
        SET tree_path = :new_path
        WHERE tree_path = :old_path
      SQL

      self.class.node_model.connection.update(Arel.sql(<<-SQL, tree_path_where: wildcard_path, old_path: @node_path, new_path: new_tree_path))
        UPDATE `#{self.class.node_model.table_name}`
        SET tree_path = REPLACE(tree_path, :old_path, :new_path)
        WHERE tree_path LIKE :tree_path_where
      SQL

      self.class.new(new_tree_path)
    end

    # Returns the decoded id of this tree node
    def id
      new_path_string(@node_path).id
    end

    # Returns the decoded parent id
    def parent_id
      new_path_string(@node_path).parent_id
    end

    # Returns the ids of those descendants for which this node is the father.
    def immediate_children
      path = wildcard_path
      sql = Arel.sql(<<-SQL, path: path, path2: "#{wildcard_path(path)}")
        SELECT id
        FROM `#{self.class.node_model.table_name}`
        WHERE tree_path LIKE :path
        AND tree_path NOT LIKE :path2
      SQL
      self.class.node_model.connection.select_values(sql)
    end

    # Returns a list containing the ids of this node's ancestors.
    # If the node is a root, their ancestors list is empty
    def ancestors
      ids = []
      path = new_path_string(@node_path)
      path.each_id { |id| ids << id }
      ids.pop # remove itself's id from the list
      ids
    end

    # Returns the number of ancestors above this node, a root has a depth of 0.
    def depth
      new_path_string(@node_path).depth
    end

    # Returns the ids of the nodes for which this node is an ancestor
    def descendants
      sql = Arel.sql(<<-SQL, path: wildcard_path)
        SELECT id
        FROM `#{self.class.node_model.table_name}`
        WHERE tree_path LIKE :path
      SQL
      self.class.node_model.connection.select_values(sql)
    end

    # Returns the id of the farthest ancestor of this node
    def root
      path = new_path_string(@node_path)
      path.each_id { |id| return id }
      nil
    end

    # API-private. This must not be called from the outside, of this class'
    # instance or class methods.
    #
    # Inserts a new node under the current node
    #
    # id: the id of the row that will be added under this tree node.
    #
    def insert(id)
      path = new_path_string(@node_path).append(id)
      affected_rows = self.class.node_model.connection.update(Arel.sql(<<-SQL, id: id, tree_path: path))
        UPDATE `#{self.class.node_model.table_name}`
        SET tree_path = :tree_path
        WHERE id = :id
      SQL
      if affected_rows > 0
        self.class.new(path)
      else
        nil
      end
    end

    protected

    def new_path_string(path)
      path = PathString.new(path, delimiter: DEFAULT_DELIMITER)
    end

    private

    def wildcard_path(path = @node_path)
      raise InvalidWildcard, "Can't get a wildcard from an empty path" if path.blank?
      new_path_string(path).raw_append("%")
    end
  end
end
