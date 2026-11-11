# typed: strict
# frozen_string_literal: true

module Platform
  module Analyzers
    class QueryCoster
      # FieldTree is an immutable representation of a GraphQL query's field structure, used for cost and node analysis.
      # Unlike the mutable Field objects (which are built incrementally and may have incomplete parent/child links during construction),
      # FieldTree and its FieldTreeNode children provide a fully connected, immutable tree that is safe for traversal and debugging.
      # This enables reliable cost calculations and easier debugging, as the entire tree structure is known and fixed after construction.
      class FieldTree
        sig { returns(T::Array[FieldTreeNode]) }
        attr_reader :roots

        # The total number of requests that can be made by this tree.
        sig { returns(Integer) }
        attr_reader :total_request_count

        # The total number of nodes that can be returned by this tree.
        sig { returns(Integer) }
        attr_reader :total_node_count

        sig { params(roots: T::Array[FieldTreeNode]).void }
        def initialize(roots)
          @roots = T.let(roots, T::Array[FieldTreeNode])
          @total_request_count = T.let(@roots.sum(&:total_request_count), Integer)
          @total_node_count = T.let(@roots.sum(&:total_node_count), Integer)
        end

        # Search all root nodes (and their descendants) for the first node that exceeds the node limit.
        sig { params(node_limit: Integer).returns(T.nilable(FieldTreeNode)) }
        def find_first_node_count_exceeding(node_limit)
          roots.each do |root_node|
            result = root_node.find_first_node_count_exceeding(node_limit)
            return result if result
          end
          nil
        end
      end
    end
  end
end
