# typed: true
# frozen_string_literal: true
module Platform
  module Analyzers
    class QueryCoster < GraphQL::Analysis::AST::Analyzer
      def initialize(query)
        super

        @field_stack = []
        @root_fields = []
      end

      # Run this analyzer when any of these conditions is true:
      # - Internal query analysis is enabled
      # - The current target isn't `:internal`
      # - The user is specifically requesting `rateLimit`
      def analyze?
        GitHub.analyze_internal_graphql? ||
          query.context[:target] != :internal ||
          query.lookahead.selects?("rateLimit")
      end

      def on_enter_field(node, parent, visitor)
        return if visitor.skipping?

        count = find_count(node, visitor)

        if count.present? || @field_stack.empty?
          parent_type = visitor.parent_type_definition
          field_defn = visitor.field_definition
          possible_types = if parent_type.kind.abstract?
            query.possible_types(parent_type)
          else
            [parent_type]
          end
          # Make a field. It's attached to its parent during `initialize`.
          field = Field.new(
            count,
            ast_node: node,
            parent: @field_stack.last,
            parent_type: parent_type,
            possible_types: possible_types,
            field_defn: field_defn,
          )

          # If this is an entry point, record it.
          if @field_stack.empty?
            @root_fields.push(field)
          end
          @field_stack.push(field)
        end
      end

      def on_leave_field(node, parent, visitor)
        return if visitor.skipping?

        count = find_count(node, visitor)

        if count.present?
          @field_stack.pop
        end
      end

      def result
        node_limit = if query.context[:origin] == Platform::ORIGIN_API || query.context[:origin] == Platform::ORIGIN_REST_API
          Platform::MAX_NODE_COUNT_EXTERNAL
        else
          Platform::MAX_NODE_COUNT_INTERNAL
        end

        total_cost = 0
        cost_breakdowns = query.context[:cost_breakdowns] = []
        @root_fields.each do |field|
          cost_breakdowns.concat(field.max_query_cost_breakdowns)
          total_cost += field.max_query_cost
        end

        # We may have a number less than 1, need to default to 1
        if total_cost < 1
          total_cost = 1
        end

        GitHub.dogstats.histogram("platform.analyzers.calculate_query_cost.query_cost", total_cost, tags: query.context[:query_tracker].dog_tags)
        query.context[:cost_total] = total_cost
        # `#rate_limit_request_query?` is set by a before_query hook, which is run _before_ analyzers are run.
        query.context[:query_tracker].query_cost = if query.context[:query_tracker].rate_limit_request_query?
          # Don't charge the client's rate limit for rate-limit-only checks.
          0
        else
          total_cost
        end

        total_node_count = 0
        node_count_breakdowns = query.context[:node_count_breakdowns] = []
        @root_fields.each do |field|
          node_count_breakdowns.concat(field.max_node_count_breakdowns)
          total_node_count += field.max_node_count
        end

        query.context[:node_count_total] = total_node_count
        GitHub.dogstats.histogram("platform.analyzers.max_node_limit.total_cost", total_node_count, tags: query.context[:query_tracker].dog_tags)

        # If we were over the node limit, find the first field which broke the node limit
        # and report it to client, preventing execution.
        if total_node_count > node_limit
          first_exceeding_field = find_first_node_count_exceeding(@root_fields, node_limit)
          if first_exceeding_field
            ast_node = first_exceeding_field.ast_node
            return Platform::Errors::MaxNodeLimitExceeded.new(first_exceeding_field.node_count, node_limit, ast_node: ast_node)
          else
            return Platform::Errors::MaxNodeLimitExceeded.new(total_node_count, node_limit)
          end
        end

        if GitHub.rate_limiting_enabled? && cost_limiter = query.context[:cost_limiter]
          at_rate_limit = cost_limiter.check(
            query.context[:query_tracker].query_cost,
            rate_limit_request_query: query.context[:query_tracker].rate_limit_request_query?,
          )

          if at_rate_limit
            query.context[:query_tracker].rate_limited!
            GitHub.dogstats.increment("platform.analyzers.rate_limit_request_query.rate_limited")
            type, id = cost_limiter.configuration.key.split("-")
            Platform::Errors::RateLimited.new("API rate limit exceeded for #{type} ID #{id}.")
          end
        end
      end

      private

      # Private: Find the field's associated before/after limit.
      # Returns number if limit is present, nil otherwise.
      def find_count(ast_node, visitor)
        arguments = visitor.arguments_for(ast_node, visitor.field_definition)
        if !arguments.is_a?(GraphQL::Schema::Validator::ValidationFailedError) && arguments.respond_to?("[]")
          arguments[:first] || arguments[:last] || arguments[:ids]&.length
        end
      end

      # Find the first field that exceeds the limit and return it (or `nil`).
      # It's a bit wasteful to re-traverse the tree, but since this is the error path,
      # I think it's ok to do a bit of extra work _here_ (in the rare case)
      # instead of tracking it elsewhere (in the common case).
      def find_first_node_count_exceeding(fields, node_limit)
        fields.each do |field|
          if field.node_count > node_limit
            # If this field exceeds the limit, return it
            return field
          elsif field.max_node_count > node_limit
            # Otherwise, check if any of its children exceeded it
            return find_first_node_count_exceeding(field.max_node_count_typed_children, node_limit)
          else
            # Neither the field nor any of its children exceeded the limit
            nil
          end
        end
        # None of these fields or their children exceeded the limit
        nil
      end
    end
  end
end
