# typed: strict
# frozen_string_literal: true

module Platform
  module Analyzers
    class QueryCoster
      class Field

        # The parent field of this field.
        sig { returns(T.nilable(QueryCoster::Field)) }
        attr_reader :parent
        protected :parent

        # The child fields of this field.
        sig { returns(T::Array[QueryCoster::Field]) }
        attr_reader :children

        # The requested node count for this field (the maximum number of nodes that this field may return).
        sig { returns(T.nilable(Integer)) }
        attr_reader :value

        sig { returns(GraphQL::Language::Nodes::Field) }
        attr_reader :ast_node

        sig { returns(GraphQL::Schema::Field) }
        attr_reader :field_defn

        sig do
          params(value: T.nilable(Integer),
            ast_node: GraphQL::Language::Nodes::Field,
            schema_parent_type: GraphQLMemberOrInterface,
            parent: T.nilable(Field),
            possible_types: T::Array[GraphQLMemberOrInterface],
            field_defn: GraphQL::Schema::Field,
            corrected_parent_request_count_enabled: T::Boolean)
          .void
        end
        def initialize(value, ast_node:, schema_parent_type:, parent:, possible_types:, field_defn:, corrected_parent_request_count_enabled:)
          @value = value
          @ast_node = ast_node
          @parent = parent
          @field_defn = field_defn
          @typed_children = T.let(Hash.new { |h, k| h[k] = [] }, T::Hash[GraphQLMemberOrInterface, T::Array[QueryCoster::Field]])
          @max_requests_calculated = T.let(false, T::Boolean)
          @possible_types = possible_types
          @schema_parent_type = schema_parent_type
          @request_count = T.let(nil, T.nilable(Integer))
          @max_request_count = T.let(0, Integer)
          @max_request_count_breakdowns = T.let([], T::Array[QueryCoster::CostBreakdown])
          @max_node_count = T.let(0, Integer)
          @max_node_count_breakdowns = T.let([], T::Array[QueryCoster::CostBreakdown])
          @max_node_count_typed_children = T.let([], T::Array[QueryCoster::Field])
          @node_count = T.let(nil, T.nilable(Integer))
          @corrected_parent_request_count_enabled = corrected_parent_request_count_enabled

          # If we have a parent to which we want to attach the field, we insert this field into the parent's typed_children.
          # Multiple fields of the same parent type will be all stored under the same typed_children element in its parent.
          # This way we will be able to calculate maximum cost among all parent + children combinations.
          if @parent.present?
            possible_types.each do |possible_type|
              (@parent.typed_children[possible_type] ||= []) << self
            end
          end

          @children = T.let([], T::Array[QueryCoster::Field])
        end

        sig { params(field: Field).void }
        def add_child(field)
          @children << field
        end

        # Number of requests made to access this field
        # PLUS maximum possible requests made for its children
        sig { returns(Integer) }
        def max_request_count
          calculate_max_request_count
          @max_request_count
        end

        # Values that make up `max_request_count`
        sig { returns(T::Array[QueryCoster::CostBreakdown]) }
        def max_request_count_breakdowns
          calculate_max_request_count
          @max_request_count_breakdowns
        end

        # Number of nodes this field may access
        # PLUS maximum nodes its children may access
        sig { returns(Integer) }
        def max_node_count
          calculate_max_request_count
          @max_node_count
        end

        # Values that make up `max_node_count`
        sig { returns(T::Array[QueryCoster::CostBreakdown]) }
        def max_node_count_breakdowns
          calculate_max_request_count
          @max_node_count_breakdowns
        end

        # This set of fields has the max node count.
        # Used for reporting field-level errors to the client.
        sig { returns(T::Array[QueryCoster::Field]) }
        def max_node_count_typed_children
          calculate_max_request_count
          @max_node_count_typed_children
        end

        # The maximum number of nodes this field may return.
        #
        # It's equal to `parent_nodes * own_nodes`
        #
        # @example Counting returned nodes
        # {
        #  viewer {
        #    repositories(first: 5) {         # <- 5 nodes
        #      nodes {
        #        issues(first: 3) {           # <- 15 nodes (5 * 3)
        #          nodes {
        #            assiginees(first: 4) {   # <- 60 nodes (15 * 4)
        #              nodes {
        #                login
        #              }
        #            }
        #          }
        #        }
        #      }
        #    }
        #  }
        #
        sig { returns(Integer) }
        def node_count
          @node_count ||= begin
            if value.nil? || value == 0
              0
            elsif @parent.nil? || @parent.node_count.nil? || @parent.node_count == 0
              # If the parent doesn't add any node count info, just use self's value
              value
            else
              # If the parent has a node count, multiply this value by the parent value
              T.must(value) * @parent.node_count
            end
          end
          T.must(@node_count)
        end

        # The number of database queries required to fulfill this field.
        #
        # Fields without parents are entry points. They only require
        # one database hit to retrieve the initial list.
        #
        # Fields with parents will require:
        #   Number of DB hits to fulfill parent * number of nodes returned by parent * 1
        #   parent.request_count                   * parent.value
        #
        # @example Counting database queries
        # {
        #  viewer {
        #    repositories(first: 5) {         # <- 1 query to fetch the list of 5
        #      nodes {
        #        issues(first: 3) {           # <- 5 queries to fetch 5 lists of 3 each
        #          nodes {
        #            assiginees(first: 4) {   # <- 15 queries to fetch 15 lists of 4 each
        #              nodes {
        #                login
        #              }
        #            }
        #          }
        #        }
        #      }
        #    }
        #  }
        #
        sig { returns(Integer) }
        def request_count
          @request_count ||= if @parent.nil? ||
            # If @corrected_parent_request_count_enabled is true, we want to skip the check for the parent's parent
            (@parent.parent.nil? && !@corrected_parent_request_count_enabled) ||
            @parent.request_count.nil? ||
            @parent.value.nil? ||
            @parent.request_count == 0 ||
            @parent.value == 0
            1
          else
            @parent.request_count * T.must(@parent.value)
          end
        end

        protected

        # For each possible return type of this node,
        # there's an entry in this hash for the fields which apply
        # to that return type.
        # Returns Hash<GraphQL::BaseType => Array<QueryCoster::Field>>
        sig { returns T::Hash[GraphQLMemberOrInterface, T::Array[QueryCoster::Field]] }
        attr_reader :typed_children

        private

        # Determine the maximum number of requests for this field,
        # caching the values in instance variables.
        sig { void }
        def calculate_max_request_count
          return if @max_requests_calculated

          @max_requests_calculated = true

          max_child_request_count = T.let(0, Integer)
          max_child_request_count_breakdowns = T.let([], T::Array[QueryCoster::CostBreakdown])
          max_child_node_count = T.let(0, Integer)
          max_child_node_count_breakdowns = T.let([], T::Array[QueryCoster::CostBreakdown])
          max_node_count_typed_children = T.let([], T::Array[QueryCoster::Field])

          # Check each possible return type of this field.
          # Track the maximum node count and maximum request count
          # among possible return types. Those are used for limiting.
          typed_children.each_value do |fields|
            request_count = fields.sum(&:max_request_count)
            node_count = fields.sum(&:max_node_count)

            # If this request count is the greatest among branches,
            # capture the value and breakdowns
            if request_count > max_child_request_count
              max_child_request_count = request_count
              max_child_request_count_breakdowns = fields.inject([]) do |memo, field|
                memo.concat(field.max_request_count_breakdowns)
                memo
              end
            end

            # If this node_count is the greatest among branches,
            # capture the value and breakdowns
            if node_count > max_child_node_count
              max_node_count_typed_children = fields
              max_child_node_count = node_count
              max_child_node_count_breakdowns = fields.inject([]) do |memo, field|
                memo.concat(field.max_node_count_breakdowns)
                memo
              end
            end
          end

          own_request_count = value ? request_count : 0
          if own_request_count > 0
            max_child_request_count_breakdowns.push(
              QueryCoster::CostBreakdown.new(
                ast_node: ast_node,
                parent_type: @schema_parent_type,
                field_defn: @field_defn,
                cost: own_request_count,
              ),
            )
          end
          @max_request_count_breakdowns = max_child_request_count_breakdowns
          @max_request_count = max_child_request_count + own_request_count

          if node_count > 0
            max_child_node_count_breakdowns.unshift(
              QueryCoster::CostBreakdown.new(
                ast_node: ast_node,
                parent_type: @schema_parent_type,
                field_defn: @field_defn,
                cost: node_count,
              ),
            )
          end
          @max_node_count_breakdowns = max_child_node_count_breakdowns
          @max_node_count = max_child_node_count + node_count
          @max_node_count_typed_children = max_node_count_typed_children
        end
      end
    end
  end
end
