# typed: true
# frozen_string_literal: true

module Platform
  module Analyzers
    class QueryCoster
      # A granular breakdown of how we "charge" for elements in a GraphQL query.
      # This is used to for RateLimit.nodeCountBreakdown and RateLimit.costBreakdown.
      class CostBreakdown
        attr_reader :cost
        def initialize(ast_node:, parent_type:, field_defn:, cost:)
          @ast_node = ast_node
          @parent_type = parent_type
          @field_defn = field_defn
          @cost = cost
        end

        def field_name
          "#{@parent_type.graphql_name}.#{@ast_node.name}"
        end

        def type_name
          @field_defn.type.unwrap.graphql_name.sub(/Edge|Connection\Z/, "")
        end

        def line
          @ast_node.line
        end

        def column
          @ast_node.col
        end
      end
    end
  end
end
