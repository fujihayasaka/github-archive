# typed: strict
# frozen_string_literal: true

module Platform
  module Analyzers
    class QueryCoster
      # A granular breakdown of how we "charge" for elements in a GraphQL query.
      # This is used to for RateLimit.nodeCountBreakdown and RateLimit.costBreakdown.
      class CostBreakdown

        sig { params(ast_node: GraphQL::Language::Nodes::AbstractNode, parent_type: GraphQLMemberOrInterface, field_defn: GraphQL::Schema::Field, cost: Integer).void }
        def initialize(ast_node:, parent_type:, field_defn:, cost:)
          @ast_node = ast_node
          @parent_type = parent_type
          @field_defn = field_defn
          @cost = cost
        end

        sig { returns(Integer) }
        attr_reader :cost

        sig { returns(String) }
        def field_name
          "#{T.unsafe(@parent_type).graphql_name}.#{@field_defn.name}"
        end

        sig { returns(String) }
        def type_name
          unwrapped_type = T.let(@field_defn.type.unwrap, GraphQLMemberOrInterface)
          graphql_type_name = T.let(T.unsafe(unwrapped_type).graphql_name, String)
          graphql_type_name.sub(/Edge|Connection\Z/, "")
        end

        sig { returns(Integer) }
        def line
          @ast_node.line
        end

        sig { returns(Integer) }
        def column
          @ast_node.col
        end
      end
    end
  end
end
