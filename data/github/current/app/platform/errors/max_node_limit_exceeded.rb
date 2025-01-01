# typed: strict
# frozen_string_literal: true

module Platform
  module Errors
    # Public: Thrown when the client requests more nodes than the max node count.
    class MaxNodeLimitExceeded < Errors::Analysis
      include ActionView::Helpers::NumberHelper

      sig { params(total_node_count: Integer, limit: Integer, node: T.nilable(Platform::Analyzers::QueryCoster::FieldTreeNode)).void }
      def initialize(total_node_count:, limit:, node: nil)

        field_ast_node = T.let(nil, T.nilable(GraphQL::Language::Nodes::Field))
        node_count = T.let(nil, T.nilable(Integer))
        # If the provided node isn't nil and it's for a field (as opposed to an inline fragment), we can use its node count for the error message.
        # Otherwise, we use the total node count of the query.
        if node && node.field.ast_node.is_a?(GraphQL::Language::Nodes::Field)
          field_ast_node = T.cast(node.field.ast_node, GraphQL::Language::Nodes::Field)
          node_count = node.field.node_count
        else
          node_count = total_node_count
        end

        formatted_max_node_count = T.let(number_with_delimiter(limit), String)
        formatted_actual_node_count = T.let(number_with_delimiter(node_count), String)

        message_beginning = if field_ast_node
          "By the time this query traverses to the #{field_ast_node.name} connection, it is requesting up to #{formatted_actual_node_count}"
        else
          "This query requests up to #{formatted_actual_node_count}"
        end

        super("MAX_NODE_LIMIT_EXCEEDED", "#{message_beginning} possible nodes which exceeds the maximum limit of #{formatted_max_node_count}.", ast_node: field_ast_node)
      end
    end
  end
end
