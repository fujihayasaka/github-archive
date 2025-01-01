# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    # Public: Thrown when the client requests more nodes than the max node count.
    class MaxNodeLimitExceeded < Errors::Analysis
      include ActionView::Helpers::NumberHelper

      def initialize(node_count, limit, ast_node: nil)
        formatted_max_node_count = number_with_delimiter(limit)
        formatted_actual_node_count = number_with_delimiter(node_count)
        message_beginning = if ast_node
          "By the time this query traverses to the #{ast_node.name} connection, it is requesting up to #{formatted_actual_node_count}"
        else
          "This query requests up to #{formatted_actual_node_count}"
        end

        super("MAX_NODE_LIMIT_EXCEEDED", "#{message_beginning} possible nodes which exceeds the maximum limit of #{formatted_max_node_count}.", ast_node: ast_node)
      end
    end
  end
end
