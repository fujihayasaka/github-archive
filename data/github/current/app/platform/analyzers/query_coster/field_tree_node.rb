# typed: strict
# frozen_string_literal: true

module Platform
  module Analyzers
    class QueryCoster
      # FieldTreeNode is an immutable node in the FieldTree, representing a single field in a GraphQL query.
      # It wraps a Field object and recursively contains child FieldTreeNodes for each child field.
      # Unlike Field, which is mutable and built incrementally, FieldTreeNode is fully connected at construction time,
      # making it safe for traversal, debugging, and cost analysis without risk of incomplete parent/child relationships.
      class FieldTreeNode
        sig { returns(Platform::Analyzers::QueryCoster::Field) }
        attr_reader :field

        # The child nodes of this field
        sig { returns T::Array[FieldTreeNode] }
        attr_reader :children

        # The parent node of this field
        sig { returns(T.nilable(FieldTreeNode)) }
        attr_reader :parent

        # The number of nodes that this field may return.
        sig { returns(Integer) }
        attr_reader :own_node_count

        # The number of requests that are expected to be made for this field.
        # This is essentially the return counts of all parent nodes multiplied together.
        sig { returns(Integer) }
        attr_reader :own_request_count

        # The maximum request count for this node and its children.
        # This is the sum of the request count of this node and the maximum request count of all children.
        sig { returns(Integer) }
        attr_reader :max_request_count

        # The maximum node count for this node and its children.
        # This is the sum of the node count of this node and the maximum node count of all children.
        sig { returns(Integer) }
        attr_reader :max_node_count


        sig { params(field: Platform::Analyzers::QueryCoster::Field, parent: T.nilable(Platform::Analyzers::QueryCoster::FieldTreeNode)).void }
        def initialize(field, parent)
          @children = T.let([], T::Array[FieldTreeNode])
          @field = T.let(field, Platform::Analyzers::QueryCoster::Field)

          @parent = T.let(parent, T.nilable(Platform::Analyzers::QueryCoster::FieldTreeNode))

          # Recursively build the rest of the tree from the field's children.
          field.children.each do |child_field|
            child_node = FieldTreeNode.new(child_field, self)
            @children << child_node
          end

          @own_node_count = T.let(field.node_count, Integer)
          @own_request_count = T.let(field.request_count, Integer)
          @max_request_count = T.let(field.max_request_count, Integer)
          @max_node_count = T.let(field.max_node_count, Integer)
        end

        # Allows for easier debugging of the tree structure.
        sig { override.returns(String) }
        def to_s
          field_name = T.let(@field.ast_node.name, String)
          field_value = @field.value.nil? ? "nil" : @field.value.to_s
          "#{field_name}(value: #{field_value})"
        end

        # Allows for easier debugging of the tree structure.
        sig { override.returns(String) }
        def inspect
          to_s
        end

        # Recursively search this node and its children for the first node where
        # the underlying field's node_count exceeds the given limit.
        sig { params(node_limit: Integer).returns(T.nilable(FieldTreeNode)) }
        def find_first_node_count_exceeding(node_limit)
          # Check if this node's field exceeds the limit.
          if @own_node_count > node_limit
            return self
          end

          # Otherwise, recurse over children.
          children.each do |child|
            result = child.find_first_node_count_exceeding(node_limit)
            return result if result
          end

          nil
        end
      end
    end
  end
end
