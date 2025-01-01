# typed: true
# frozen_string_literal: true

# The main idea of how this QueryCoster works is the following:
# Find fields in the query which we can calculate the cost of. Currently, it's only connection fields.
# Push those fields into array (below in comments I call it a "tree") that we will later iterate over.
# Each field in this array has:
#   - parent, which is a previous field in the array
#   - children, whose types are being calculated based on a query structure.
# Each combination of the field with each of its typed children is considred a "branch". Every branch has its cost to get asked objects and estimated amount of returned objects.
# We pick the most expensive branches to determine whether we need to rate limit the query.
# In `result` method, we analyze the total cost and total estimated objects count, and rate limit request if any of those exceeds the limit.
# Exact cost of each field is calculated in app/platform/analyzers/query_coster/field.rb.
module Platform
  module Analyzers
    class QueryCoster < GraphQL::Analysis::AST::Analyzer
      MAX_32_INT = 2**31 - 1 # 2,147,483,647

      def initialize(query)
        super

        @field_stack = []
        @root_fields = []

        # Temporary arrays to track potential query costs
        @field_stack_list_complexity = []
        @root_fields_list_complexity = []
        @field_stack_with_corrected_branch_detection = []
        @root_fields_with_corrected_branch_detection = []

        # Evaluate all feature flags before any calculations
        if analyze?
          @corrected_branch_detection = GitHub.flipper[:graphql_corrected_branch_detection_in_query_coster].enabled?
          @track_potential_query_costs = GitHub.flipper[:graphql_track_potential_query_costs].enabled?
          @count_list_complexity = GitHub.flipper[:graphql_count_list_complexity].enabled?
        end
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

      # Adds currently analyzed field to the tree that we will be using for query cost calcuation.
      def on_enter_field(node, parent, visitor)
        return if visitor.skipping?

        field_defn = visitor.field_definition
        # the type which the current type came from. This corresponds to schema definition.
        schema_parent_type = visitor.parent_type_definition

        # possible types of the parent type, which are used for branch detection.
        possible_types = find_possible_types(schema_parent_type, @field_stack)

        requested_nodes_count = find_requested_nodes_count(node, visitor)

        # if current field is field we can calculate cost of, or if it's a first field of the query, we want to add it to the tree.
        if requested_nodes_count.present? || @field_stack.empty?

          # Make a field. It's attached to its parent during `initialize`.
          field = Field.new(
            requested_nodes_count,
            ast_node: node,
            parent: @field_stack.last,
            schema_parent_type: schema_parent_type,
            possible_types: possible_types,
            field_defn: field_defn,
          )

          # If this is an entry point, record it.
          if @field_stack.empty?
            @root_fields.push(field)
          end
          @field_stack.push(field)
        end

        if @track_potential_query_costs
          # This is temporary code for tracking the potential query costs for customised list complexity counts.
          # It'll be removed once the graphql_count_list_complexity feature flag is removed.
          requested_nodes_count_with_lists_complexity = find_requested_nodes_count_with_list_complexity(node, visitor)
          if requested_nodes_count_with_lists_complexity.present? || @field_stack_list_complexity.empty?
            field = Field.new(
              requested_nodes_count_with_lists_complexity,
              ast_node: node,
              parent: @field_stack_list_complexity.last,
              schema_parent_type: schema_parent_type,
              possible_types: possible_types,
              field_defn: field_defn,
            )

            if @field_stack_list_complexity.empty?
              @root_fields_list_complexity.push(field)
            end
            @field_stack_list_complexity.push(field)
          end

          # This is temporary code for tracking the potential query costs for corrected branch detection.
          # It'll be removed once the graphql_corrected_branch_detection_in_query_coster feature flag is removed.
          if requested_nodes_count.present? || @field_stack_with_corrected_branch_detection.empty?
            possible_types_with_corrected_branch_detection = find_possible_types_with_corrected_branch_detection(schema_parent_type, @field_stack_with_corrected_branch_detection)
            field = Field.new(
              requested_nodes_count,
              ast_node: node,
              parent: @field_stack_with_corrected_branch_detection.last,
              schema_parent_type: schema_parent_type,
              possible_types: possible_types_with_corrected_branch_detection,
              field_defn: field_defn,
            )

            if @field_stack_with_corrected_branch_detection.empty?
              @root_fields_with_corrected_branch_detection.push(field)
            end
            @field_stack_with_corrected_branch_detection.push(field)
          end
        end
      end

      def on_leave_field(node, parent, visitor)
        return if visitor.skipping?

        count = find_requested_nodes_count(node, visitor)
        if count.present?
          @field_stack.pop
        end

        if @track_potential_query_costs
          count_with_list_complexity = find_requested_nodes_count_with_list_complexity(node, visitor)
          if count_with_list_complexity.present?
            @field_stack_list_complexity.pop
          end

          if count.present?
            @field_stack_with_corrected_branch_detection.pop
          end
        end
      end

      def result
        node_limit = if query.context[:origin] == Platform::ORIGIN_API || query.context[:origin] == Platform::ORIGIN_REST_API
          Platform::MAX_NODE_COUNT_EXTERNAL
        else
          Platform::MAX_NODE_COUNT_INTERNAL
        end

        total_request_count = 0
        cost_breakdowns = query.context[:cost_breakdowns] = []
        @root_fields.each do |field|
          cost_breakdowns.concat(field.max_request_count_breakdowns)
          total_request_count += field.max_request_count
        end

        query_cost_score = calculate_query_cost_score(total_request_count)

        # The resulting score shouldn't be lower than 1.
        if query_cost_score < 1
          query_cost_score = 1
        end

        GitHub.dogstats.histogram("platform.analyzers.calculate_query_cost.query_cost", query_cost_score, tags: query.context[:query_tracker].dog_tags)
        query.context[:cost_total] = query_cost_score
        # `#rate_limit_request_query?` is set by a before_query hook, which is run _before_ analyzers are run.
        query.context[:query_tracker].query_cost = if query.context[:query_tracker].rate_limit_request_query?
          # Don't charge the client's rate limit for rate-limit-only checks.
          0
        else
          query_cost_score
        end

        total_node_count = 0
        node_count_breakdowns = query.context[:node_count_breakdowns] = []
        @root_fields.each do |field|
          node_count_breakdowns.concat(field.max_node_count_breakdowns)
          total_node_count += field.max_node_count
        end

        # If this feature flag is enabled, we want to track the potential query scores.
        # The goal is to understand the potential impact on query costs after our bugs fixes.
        if @track_potential_query_costs

          # Only calculate the potential list complexity scores if the related feature flag is disabled.
          # To be removed when the graphql_count_list_complexity feature flag is removed.
          potential_list_complexity_score = nil
          potential_list_complexity_node_count_exceeding = nil
          if !@count_list_complexity

            total_request_count_list_complexity = 0
            total_node_count_list_complexity = 0
            @root_fields_list_complexity.each do |field|
              total_request_count_list_complexity += field.max_request_count
              total_node_count_list_complexity += field.max_node_count
            end

            potential_list_complexity_score = calculate_query_cost_score(total_request_count_list_complexity)

            # We sometimes see extremely large values for potential_complexity_cost_with_list_complexity which exceed the max value of int32, causing Hydro serialization errors.
            # So we are clamping the value of potential_list_complexity_score to the max int32 value.
            # See issue for more details: https://github.com/github/graphql-platform/issues/1272
            potential_list_complexity_score = [potential_list_complexity_score, MAX_32_INT.to_i].min

            # we can also reject the query if the node count exceeds the node limit, and new list complexity can affect this as well, so let's track it.
            potential_list_complexity_node_count_exceeding = total_node_count_list_complexity > node_limit
          end

          # Only calculate the potential corrected branch detection scores and new node count if the related feature flag is disabled.
          # To be removed when the graphql_corrected_branch_detection_in_query_coster feature flag is removed.
          potential_corrected_branch_detection_score = nil
          total_node_count_branch_detection = nil
          if !@corrected_branch_detection
            total_request_count_corrected_branch_detection = 0
            total_node_count_branch_detection = 0
            @root_fields_with_corrected_branch_detection.each do |field|
              total_request_count_corrected_branch_detection += field.max_request_count
              total_node_count_branch_detection += field.max_node_count
            end
            potential_corrected_branch_detection_score = calculate_query_cost_score(total_request_count_corrected_branch_detection)
          end

          potential_query_scores = PotentialQueryCosts.new(
            custom_list_complexity: potential_list_complexity_score,
            custom_list_complexity_node_count_exceeding: potential_list_complexity_node_count_exceeding,
            corrected_branch_detection: potential_corrected_branch_detection_score,
            total_node_count_branch_detection: total_node_count_branch_detection
          )
          track_potential_query_scores(potential_query_scores)
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

      sig { params(potential_query_scores: Platform::Analyzers::QueryCoster::PotentialQueryCosts).void }
      def track_potential_query_scores(potential_query_scores)
        # Log each potential query score to Datadog.
        potential_query_scores.to_hash.each do |key, value|
          if value.nil?
            next
          end

          # If the value is a boolean, we need to convert it to a number
          if [true, false].include?(value)
            value = value ? 1 : 0
          end

          GitHub.dogstats.histogram("platform.analyzers.calculate_query_cost.potential_query_cost.#{key}", value, tags: query.context[:query_tracker].dog_tags)
        end

        # Add the potential costs to the query context so they can be logged to Hydro.
        query.context[:query_tracker].potential_query_costs = potential_query_scores
      end

      # Private: Find how many nodes have been requested for a field.
      # Returns number if limit is present, nil otherwise.
      sig { params(ast_node: T.untyped, visitor: T.untyped).returns(T.nilable(Integer)) }
      def find_requested_nodes_count(ast_node, visitor)
        if @count_list_complexity
          find_requested_nodes_count_with_list_complexity(ast_node, visitor)
        else
          find_requested_nodes_count_without_list_complexity(ast_node, visitor)
        end
      end

      # Private: Find how many nodes have been requested for a field, assuming list complexity is enabled.
      sig { params(ast_node: T.untyped, visitor: T.untyped).returns(T.nilable(Integer)) }
      def find_requested_nodes_count_with_list_complexity(ast_node, visitor)
        field_definition = visitor.field_definition
        field_name = ast_node.name
        count = nil

        # filters out nodes + edges & internal ratelimiting breakdown list fields from getting lists complexities
        if field_definition.type.list? && !%w[nodes edges costBreakdowns nodeCountBreakdowns].include?(field_name)
          # default complexity for fields is 1: https://graphql-ruby.org/api-doc/1.8.13/GraphQL/Field.html#complexity-instance_method.
          # but we want default Lists complexity to be Platform::DEFAULT_LIST_COST, or another custom one, but not 1.
          count = field_definition.complexity == 1 ? Platform::DEFAULT_LIST_COST : field_definition.complexity
        end

        arguments = visitor.arguments_for(ast_node, field_definition)
        if !arguments.is_a?(GraphQL::Schema::Validator::ValidationFailedError) && arguments.respond_to?("[]")
          new_count = arguments[:first] || arguments[:last] || arguments[:ids]&.length
          count = new_count if new_count
        end

        count
      end

      # Private: Find how many nodes have been requested for a field, assuming list complexity is not enabled.
      sig { params(ast_node: T.untyped, visitor: T.untyped).returns(T.nilable(Integer)) }
      def find_requested_nodes_count_without_list_complexity(ast_node, visitor)
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

      # Calculates the query cost score by dividing the total request count by 100 and rounding to the nearest whole number,
      # as described in our public docs here: https://docs.github.com/en/graphql/overview/rate-limits-and-node-limits-for-the-graphql-api#predicting-the-point-value-of-a-query
      sig { params(request_count: Integer).returns(Integer) }
      def calculate_query_cost_score(request_count)
        (request_count / 100.0).round
      end

      def find_possible_types_with_corrected_branch_detection(schema_parent_type, field_stack)
        # This branch does essentially the same as the one below, with one modification:
        # when the fields are nested, we need to attach it not to parent based on schema, but to the parent that is in the tree for query cost calculation.
        # That prevents incorrect detection of typed children and therefore incorrect branch cost calculation.
        # It's a fix for https://github.com/github/graphql-platform/issues/853.
        # analyzer_parent_type is either schema parent type for a root field, or type of the last field in the tree.
        analyzer_parent_type = field_stack.last.nil? ? schema_parent_type : field_stack.last.field_defn.type.unwrap

        # if the type of the last field in the tree is abstract, we need to calculate the possible types for it based on schema.
        possible_types = if analyzer_parent_type.kind.abstract?
          query.possible_types(schema_parent_type)
        else
          # otherwise, we want to attach node directly to this type.
          [analyzer_parent_type]
        end
        possible_types
      end

      def find_possible_types(schema_parent_type, field_stack)
        if @corrected_branch_detection
          possible_types = find_possible_types_with_corrected_branch_detection(schema_parent_type, field_stack)
        else
          # in order to connect child and parent we need to know which types parent can be, because sometimes parent
          # is just an abstract Node that can return multiple types of objects.
          # This logic goes a bit backwards because in field.rb we insert child node (the one we analyze now) into parent.
          possible_types = if schema_parent_type.kind.abstract?
            query.possible_types(schema_parent_type)
          else
            [schema_parent_type]
          end
        end
        possible_types
      end
    end
  end
end
