# typed: true
# frozen_string_literal: true

module Platform
  module Analyzers
    class QueryCoster
      class Field
        attr_reader :ast_node, :field_defn

        def initialize(value, ast_node:, schema_parent_type:, parent:, possible_types:, field_defn:)
          @value = value
          @ast_node = ast_node
          @parent = parent
          @field_defn = field_defn
          @typed_children = Hash.new { |h, k| h[k] = [] }
          @max_requests_calculated = false
          @possible_types = possible_types
          @schema_parent_type = schema_parent_type

          # If we have a parent to which we want to attach the field, we insert this field into the parent's typed_children.
          # Multiple fields of the same parent type will be all stored under the same typed_children element in its parent.
          # This way we will be able to calculate maximum cost among all parent + children combinations.
          if @parent.present?
            possible_types.each do |possible_type|
              @parent.typed_children[possible_type] << self
            end
          end
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
              value * @parent.node_count
            end
          end
        end

        protected

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
          @request_count ||= if @parent.nil? || @parent.parent.nil?
            1
          else
            parent.request_count * parent.value
          end
        end

        # The previous node which has a `value`, if there is one.
        # Returns QueryCoster::Field or nil
        attr_reader :parent

        # The number of nodes this field may return
        # Returns Integer
        attr_reader :value

        # For each possible return type of this node,
        # there's an entry in this hash for the fields which apply
        # to that return type.
        # Returns Hash<GraphQL::BaseType => Array<QueryCoster::Field>>
        attr_reader :typed_children

        private

        # Determine the maximum number of requests for this field,
        # caching the values in instance variables.
        def calculate_max_request_count
          return if @max_requests_calculated

          @max_requests_calculated = true

          max_child_request_count = T.let(0, Integer)
          max_child_request_count_breakdowns = T.let(nil, T.untyped)
          max_child_node_count = T.let(0, Integer)
          max_child_node_count_breakdowns = T.let(nil, T.untyped)
          max_node_count_typed_children = T.let(nil, T.untyped)

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

          # If no children costed more than 0
          # (or if there were no children at all)
          # we need an empty array which may contain `self`
          max_child_request_count_breakdowns ||= []
          max_child_node_count_breakdowns ||= []

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
          @max_node_count_typed_children = max_node_count_typed_children || NO_TYPED_CHILDREN
        end

        # Use this for `max_node_count_typed_children` when a node
        # had no children or no children which have any cost.
        #
        # By using a constant, we avoid needlessly allocating an array.
        NO_TYPED_CHILDREN = [].freeze
      end
    end
  end
end
