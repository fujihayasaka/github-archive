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

      # Adds currently analyzed field to the tree that we will be using for query cost calcuation.
      def on_enter_field(node, parent, visitor)
        return if visitor.skipping?

        requested_nodes_count = find_requested_nodes_count(node, visitor)

        # if current field is field we can calculate cost of, or if it's a first field of the query, we want to add it to the tree.
        if requested_nodes_count.present? || @field_stack.empty?
          field_defn = visitor.field_definition

          # the type which the current type came from. This corresponds to schema definition.
          schema_parent_type = visitor.parent_type_definition

          if GitHub.flipper[:graphql_corrected_branch_detection_in_query_coster].enabled?
            # This branch does essentially the same as the one below, with one modification:
            # when the fields are nested, we need to attach it not to parent based on schema, but to the parent that is in the tree for query cost calculation.
            # That prevents incorrect detection of typed children and therefore incorrect branch cost calculation.
            # It's a fix for https://github.com/github/graphql-platform/issues/853.
            # analyzer_parent_type is either schema parent type for a root field, or type of the last field in the tree.
            analyzer_parent_type = @field_stack.last.nil? ? schema_parent_type : @field_stack.last.field_defn.type.unwrap

            # if the type of the last field in the tree is abstract, we need to calculate the possible types for it based on schema.
            possible_types = if analyzer_parent_type.kind.abstract?
              query.possible_types(schema_parent_type)
            else
              # otherwise, we want to attach node directly to this type.
              [analyzer_parent_type]
            end
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
      end

      def on_leave_field(node, parent, visitor)
        return if visitor.skipping?

        count = find_requested_nodes_count(node, visitor)

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

        total_request_count = 0
        cost_breakdowns = query.context[:cost_breakdowns] = []
        @root_fields.each do |field|
          cost_breakdowns.concat(field.max_request_count_breakdowns)
          total_request_count += field.max_request_count
        end

        # Feature flag for issue: https://github.com/github/graphql-platform/issues/847
        if GitHub.flipper[:graphql_corrected_query_cost_rounding].enabled?
          query_cost_score = calculate_query_cost_score_with_corrected_rounding(total_request_count)
        else
          if GitHub.flipper[:graphql_track_potential_query_costs].enabled?
            # If this feature flag is enabled, we want to track the potential query scores
            potential_query_scores = PotentialQueryCosts.new(
              corrected_rounding: calculate_query_cost_score_with_corrected_rounding(total_request_count),
            )
            track_potential_query_scores(potential_query_scores)
          end

          query_cost_score = calculate_query_cost_score_with_legacy_rounding(cost_breakdowns)
        end

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

      sig { params(total_request_count: Integer).returns(Integer) }
      def calculate_query_cost_score_with_corrected_rounding(total_request_count)
        query_score_with_corrected_rounding = calculate_query_cost_score(total_request_count)
        if query_score_with_corrected_rounding < 1
          query_score_with_corrected_rounding = 1
        end
        query_score_with_corrected_rounding
      end

      sig { params(node_count_breakdowns: T::Array[Platform::Analyzers::QueryCoster::CostBreakdown]).returns(Integer) }
      def calculate_query_cost_score_with_legacy_rounding(node_count_breakdowns)
        # This is the old and incorrect behaviour, to be removed when the graphql_corrected_query_cost_rounding feature flag is removed.
        # The query cost is calculated for each field and then summed up.
        # We have granular access to the request count of each field via the cost breakdowns,
        # where the "cost" is the request count for the field.
        query_cost_score = 0
        node_count_breakdowns.each do |breakdown|
          # For historical reasons, any count below 100 is given a cost of 0.
          if breakdown.cost >= 100
            field_cost_score = calculate_query_cost_score(breakdown.cost)
            query_cost_score += field_cost_score
          end
        end
        query_cost_score
      end

      sig { params(potential_query_scores: Platform::Analyzers::QueryCoster::PotentialQueryCosts).void }
      def track_potential_query_scores(potential_query_scores)
        # Log each potential query score to Datadog.
        potential_query_scores.to_hash.each do |key, value|
          if value.nil?
            next
          end
          GitHub.dogstats.histogram("platform.analyzers.calculate_query_cost.potential_query_cost.#{key}", value, tags: query.context[:query_tracker].dog_tags)
        end
      end

      # Private: Find how many nodes have been requested for a field.
      # Returns number if limit is present, nil otherwise.
      def find_requested_nodes_count(ast_node, visitor)
        field_definition = visitor.field_definition

        # This FF should only be enabled when the :graphql_corrected_query_cost_rounding is also enabled.
        # This allows us to count list fields with a set amount of node count so that we can
        # calculate the query cost.
        if GitHub.flipper[:graphql_count_list_complexity].enabled?
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
        else
          arguments = visitor.arguments_for(ast_node, visitor.field_definition)
          if !arguments.is_a?(GraphQL::Schema::Validator::ValidationFailedError) && arguments.respond_to?("[]")
            arguments[:first] || arguments[:last] || arguments[:ids]&.length
          end
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
    end
  end
end
