# typed: strict
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
      MAX_32_INT = T.let(2**31 - 1, Numeric) # 2,147,483,647

      sig { params(subject: T.any(GraphQL::Query, GraphQL::Execution::Multiplex)).void }
      def initialize(subject)
        super

        @field_tree_builder = T.let(FieldTreeBuilder.new, FieldTreeBuilder)

        # Temporary tree builders to track potential query costs
        @field_tree_builder_list_complexity = T.let(FieldTreeBuilder.new, FieldTreeBuilder)
        @field_tree_builder_with_corrected_branch_detection = T.let(FieldTreeBuilder.new, FieldTreeBuilder)
        @field_tree_builder_with_corrected_parent_request_count = T.let(FieldTreeBuilder.new, FieldTreeBuilder)

        # Evaluate all feature flags before any calculations
        if analyze?
          actor = T.let(subject.context[:actor], T.untyped)
          @bypass_query_coster_parent_request_count_changes = T.let(FeatureFlag.vexi.enabled?(:graphql_bypass_query_coster_parent_request_count_changes, actor, default: false), T::Boolean)
          @corrected_parent_request_count_enabled = T.let(@bypass_query_coster_parent_request_count_changes ? false : FeatureFlag.vexi.enabled?(:graphql_corrected_parent_request_count, actor, default: false), T::Boolean)

          @corrected_branch_detection = T.let(FeatureFlag.vexi.enabled?(:graphql_corrected_branch_detection_in_query_coster, actor, default: false), T::Boolean)
          @count_list_complexity = T.let(FeatureFlag.vexi.enabled?(:graphql_count_list_complexity, actor, default: false), T::Boolean)
          @track_potential_query_costs = T.let(FeatureFlag.vexi.enabled?(:graphql_track_potential_query_costs, actor, default: false), T::Boolean)
        end
      end

      # Run this analyzer when any of these conditions is true:
      # - Internal query analysis is enabled
      # - The current target isn't `:internal`
      # - The user is specifically requesting `rateLimit`
      sig { override.returns(T::Boolean) }
      def analyze?
        current_query = get_current_query(nil)
        return false if current_query.nil?
        GitHub.analyze_internal_graphql? ||
          current_query.context[:target] != :internal ||
          current_query.lookahead.selects?("rateLimit")
      end

      # Adds currently analyzed field to the tree that we will be using for query cost calcuation.
      # To demonstrate the different values, take the following example:
      # query {
      #   nodes(ids: $ids)
      #     ... on User {
      #       login
      #       name
      #       repositories(first: 5) {
      #         nodes {
      #           name
      #           description
      #         }
      #       }
      #     }
      #   }
      # }
      # Using the above example, the following values for `field_defn` and `schema_parent_type` would be:
      # - field_defn: `nodes`, type_definition: `Platform::Interfaces::Node`, schema_parent_type: `Platform::Objects::Query`, parent: query
      # - field_defn: `login`, type_definition: `GraphQL::Types::String`, schema_parent_type: `Platform::Objects::User`, parent: User
      # - field_defn: `name`, type_definition: `GraphQL::Types::String`, schema_parent_type: `Platform::Objects::User`, parent: User
      # - field_defn: `repositories`, type_definition: `Platform::Connections::Repository`, schema_parent_type: `Platform::Objects::User`, parent: User
      # - field_defn: `nodes`, type_definition: `Platform::Objects::Repository`, schema_parent_type: `Platform::Connections::Repository`, parent: repositories
      # - field_defn: `name`, type_definition: `GraphQL::Types::String`, schema_parent_type: `Platform::Objects::Repository`, parent: nodes
      # - field_defn: `description`, type_definition: `GraphQL::Types::String`, schema_parent_type: `Platform::Objects::Repository`, parent: nodes
      sig { override.params(node: GraphQL::Language::Nodes::Field, parent: T.nilable(GraphQL::Language::Nodes::AbstractNode), visitor: GraphQL::Analysis::AST::Visitor).void }
      def on_enter_field(node, parent, visitor)
        return if visitor.skipping?

        # Grab the schema definition of the current field.
        field_defn = T.let(visitor.field_definition, T.nilable(GraphQL::Schema::Field))

        # field_defn shouldn't be nil as we've entered a field, but visitor.field_definition
        # is defined as nilable, so we should check it's not nil to appease Sorbet.
        return if field_defn.nil?

        # Get the current query which owns the entered field.
        current_query = get_current_query(visitor)
        return if current_query.nil?

        # the object type which the current field belongs to.
        # Note: you can retrieve the type of the field by using `type_definition = T.let(visitor.type_definition, GraphQLMemberOrInterface)` instead.
        schema_parent_type = T.let(visitor.parent_type_definition, GraphQLMemberOrInterface)

        # possible types of the parent type, which are used for branch detection.
        possible_types = find_possible_types(schema_parent_type, @field_tree_builder.active_field, current_query)

        requested_nodes_count = find_requested_nodes_count(node, visitor)

        # if current field is a field we can calculate a cost of, or if it's a first field of the query, we want to add it to the tree.
        if requested_nodes_count.present? || @field_tree_builder.active_field.nil?
          # Make a field. It's attached to its parent during `initialize`.
          field = Field.new(
            requested_nodes_count,
            ast_node: node,
            parent: @field_tree_builder.active_field,
            schema_parent_type: schema_parent_type,
            possible_types: possible_types,
            field_defn: field_defn,
            corrected_parent_request_count_enabled: @corrected_parent_request_count_enabled
          )

          @field_tree_builder.enter_field(field)
        end

        if @track_potential_query_costs
          # This is temporary code for tracking the potential query costs for customised list complexity counts.
          # It'll be removed once the graphql_count_list_complexity feature flag is removed.
          requested_nodes_count_with_lists_complexity = find_requested_nodes_count_with_list_complexity(node, visitor)
          if requested_nodes_count_with_lists_complexity.present? || @field_tree_builder_list_complexity.active_field.nil?
            field = Field.new(
              requested_nodes_count_with_lists_complexity,
              ast_node: node,
              parent: @field_tree_builder_list_complexity.active_field,
              schema_parent_type: schema_parent_type,
              possible_types: possible_types,
              field_defn: field_defn,
              corrected_parent_request_count_enabled: @corrected_parent_request_count_enabled
            )

            @field_tree_builder_list_complexity.enter_field(field)
          end

          # This is temporary code for tracking the potential query costs for corrected branch detection.
          # It'll be removed once the graphql_corrected_branch_detection_in_query_coster feature flag is removed.
          if requested_nodes_count.present? || @field_tree_builder_with_corrected_branch_detection.active_field.nil?
            parent_field = @field_tree_builder_with_corrected_branch_detection.active_field
            possible_types_with_corrected_branch_detection = find_possible_types_with_corrected_branch_detection(schema_parent_type, parent_field, current_query)
            field = Field.new(
              requested_nodes_count,
              ast_node: node,
              parent: parent_field,
              schema_parent_type: schema_parent_type,
              possible_types: possible_types_with_corrected_branch_detection,
              field_defn: field_defn,
              corrected_parent_request_count_enabled: @corrected_parent_request_count_enabled
            )
            @field_tree_builder_with_corrected_branch_detection.enter_field(field)
          end

          # This is temporary code for tracking the potential query costs for corrected request count calculations.
          # It'll be removed once the graphql_corrected_parent_request_count feature flag is removed.
          if requested_nodes_count.present? || @field_tree_builder_with_corrected_parent_request_count.active_field.nil?
            field = Field.new(
              requested_nodes_count,
              ast_node: node,
              parent: @field_tree_builder_with_corrected_parent_request_count.active_field,
              schema_parent_type: schema_parent_type,
              possible_types: possible_types,
              field_defn: field_defn,
              corrected_parent_request_count_enabled: true
            )
            @field_tree_builder_with_corrected_parent_request_count.enter_field(field)
          end
        end
      end

      sig { override.params(node: GraphQL::Language::Nodes::Field, parent: T.nilable(GraphQL::Language::Nodes::AbstractNode), visitor: GraphQL::Analysis::AST::Visitor).void }
      def on_leave_field(node, parent, visitor)
        return if visitor.skipping?

        count = find_requested_nodes_count(node, visitor)
        if count.present?
          @field_tree_builder.exit_field
        end

        if @track_potential_query_costs
          count_with_list_complexity = find_requested_nodes_count_with_list_complexity(node, visitor)
          if count_with_list_complexity.present?
            @field_tree_builder_list_complexity.exit_field
          end

          if count.present?
            @field_tree_builder_with_corrected_branch_detection.exit_field
            @field_tree_builder_with_corrected_parent_request_count.exit_field
          end
        end
      end

      sig { override.returns(T.nilable(GraphQL::AnalysisError)) }
      def result
        current_query = get_current_query(nil)
        return if current_query.nil?

        # Build the final query field tree from the builder.
        field_tree = @field_tree_builder.build

        # Track query metrics
        track_query_metrics(field_tree, current_query)

        query_tracker = T.let(current_query.context[:query_tracker], Platform::QueryTracker)
        query_tracker.bypass_query_coster_parent_request_count_changes = @bypass_query_coster_parent_request_count_changes

        # If this feature flag is enabled, we want to track potential query metrics.
        # The goal is to understand the potential impact on query costs after our bugs fixes.
        if @track_potential_query_costs
          potential_query_scores = calculate_potential_query_costs(current_query)
          track_potential_query_scores(query_tracker, potential_query_scores)
        end

        # Validate the query
        validate_query_field_tree(field_tree, current_query)
      end

      private

      # This overrides the field on the superclass but adds type safety.
      # Please see these comments for an explanation of when this can be nil (when the subject is a GraphQL::Execution::Multiplex):
      # https://github.com/rmosolgo/graphql-ruby/blob/3664b848455ef73f3c79fcb389f5832edc997840/lib/graphql/analysis/analyzer.rb#L82-L84
      # NOTE: Do not access this directly, please use `get_current_query` instead.
      sig { override.returns(T.nilable(GraphQL::Query)) }
      def query
        super
      end

      sig { params(field_tree: FieldTree, current_query: GraphQL::Query).void }
      def track_query_metrics(field_tree, current_query)
        track_query_cost_breakdowns(field_tree, current_query)
        query_cost_score = calculate_query_cost_score(field_tree.max_request_count)
        track_query_cost_score(query_cost_score, current_query)

        track_query_node_count_breakdowns(field_tree, current_query)
        total_node_count = field_tree.max_node_count
        track_query_total_node_count(total_node_count, current_query)

        total_request_count = field_tree.max_request_count
        current_query.context[:request_count_total] = total_request_count
      end

      sig { params(field_tree: FieldTree, current_query: GraphQL::Query).returns(T.nilable(GraphQL::AnalysisError)) }
      def validate_query_field_tree(field_tree, current_query)
        total_node_count = field_tree.max_node_count
        # If we were over the node limit, find the first field which broke the node limit
        # and report it to client, preventing execution.
        node_limit = get_node_limit(current_query)
        if total_node_count > node_limit
          first_exceeding_node = field_tree.find_first_node_count_exceeding(node_limit)
          return Platform::Errors::MaxNodeLimitExceeded.new(total_node_count: total_node_count, limit: node_limit, node: first_exceeding_node)
        end

        if GitHub.rate_limiting_enabled? && cost_limiter = current_query.context[:cost_limiter]
          at_rate_limit = cost_limiter.check(
            current_query.context[:query_tracker].query_cost,
            rate_limit_request_query: current_query.context[:query_tracker].rate_limit_request_query?,
          )

          if at_rate_limit
            current_query.context[:query_tracker].rate_limited!
            GitHub.dogstats.increment("platform.analyzers.rate_limit_request_query.rate_limited")
            type, id = cost_limiter.configuration.key.split("-")
            Platform::Errors::RateLimited.new("API rate limit exceeded for #{type} ID #{id}.")
          end
        end
      end

      sig { params(current_query: GraphQL::Query).returns(Integer) }
      def get_node_limit(current_query)
        if current_query.context[:origin] == Platform::ORIGIN_API || current_query.context[:origin] == Platform::ORIGIN_REST_API
          Platform::MAX_NODE_COUNT_EXTERNAL
        else
          Platform::MAX_NODE_COUNT_INTERNAL
        end
      end

      sig { params(current_query: GraphQL::Query).returns(PotentialQueryCosts) }
      def calculate_potential_query_costs(current_query)
        # Only calculate the potential list complexity scores if the related feature flag is disabled.
        # To be removed when the graphql_count_list_complexity feature flag is removed.
        potential_list_complexity_score = nil
        potential_list_complexity_node_count_exceeding = nil
        if !@count_list_complexity

          total_request_count_list_complexity = 0
          total_node_count_list_complexity = 0

          # Build the final field tree from the list complexity builder.
          field_tree_list_complexity = @field_tree_builder_list_complexity.build
          total_request_count_list_complexity = field_tree_list_complexity.max_request_count
          total_node_count_list_complexity = field_tree_list_complexity.max_node_count
          potential_list_complexity_score = calculate_query_cost_score(total_request_count_list_complexity)

          # We sometimes see extremely large values for potential_complexity_cost_with_list_complexity which exceed the max value of int32, causing Hydro serialization errors.
          # So we are clamping the value of potential_list_complexity_score to the max int32 value.
          # See issue for more details: https://github.com/github/graphql-platform/issues/1272
          potential_list_complexity_score = [potential_list_complexity_score, MAX_32_INT.to_i].min

          # we can also reject the query if the node count exceeds the node limit, and new list complexity can affect this as well, so let's track it.
          potential_list_complexity_node_count_exceeding = total_node_count_list_complexity > get_node_limit(current_query)
        end

        # Only calculate the potential corrected branch detection scores and new node count if the related feature flag is disabled.
        # To be removed when the graphql_corrected_branch_detection_in_query_coster feature flag is removed.
        potential_corrected_branch_detection_score = nil
        total_node_count_branch_detection = nil
        if !@corrected_branch_detection
          total_request_count_corrected_branch_detection = 0
          total_node_count_branch_detection = 0

          # Build the final field tree from the corrected branch detection builder.
          field_tree_with_corrected_branch_detection = @field_tree_builder_with_corrected_branch_detection.build
          total_request_count_corrected_branch_detection = field_tree_with_corrected_branch_detection.max_request_count
          total_node_count_branch_detection = field_tree_with_corrected_branch_detection.max_node_count
          potential_corrected_branch_detection_score = calculate_query_cost_score(total_request_count_corrected_branch_detection)
        end

        potential_parent_request_count = nil
        if !@corrected_parent_request_count_enabled
          # Build the final field tree from the corrected parent request count builder.
          field_tree_with_corrected_parent_request_count = @field_tree_builder_with_corrected_parent_request_count.build
          potential_parent_request_count = field_tree_with_corrected_parent_request_count.max_request_count
        end

        potential_query_scores = PotentialQueryCosts.new(
          custom_list_complexity: potential_list_complexity_score,
          custom_list_complexity_node_count_exceeding: potential_list_complexity_node_count_exceeding,
          corrected_branch_detection: potential_corrected_branch_detection_score,
          total_node_count_branch_detection: total_node_count_branch_detection,
          corrected_parent_request_count: potential_parent_request_count
        )
        potential_query_scores
      end

      sig { params(total_node_count: Integer, current_query: GraphQL::Query).void }
      def track_query_total_node_count(total_node_count, current_query)
        current_query.context[:node_count_total] = total_node_count
        GitHub.dogstats.histogram("platform.analyzers.max_node_limit.total_cost", total_node_count, tags: current_query.context[:query_tracker].dog_tags)
      end

      sig { params(query_cost_score: Integer, current_query: GraphQL::Query).void }
      def track_query_cost_score(query_cost_score, current_query)
        GitHub.dogstats.histogram("platform.analyzers.calculate_query_cost.query_cost", query_cost_score, tags: current_query.context[:query_tracker].dog_tags)
        current_query.context[:cost_total] = query_cost_score
        # `#rate_limit_request_query?` is set by a before_query hook, which is run _before_ analyzers are run.
        current_query.context[:query_tracker].query_cost = if current_query.context[:query_tracker].rate_limit_request_query?
          # Don't charge the client's rate limit for rate-limit-only checks.
          0
        else
          query_cost_score
        end
      end

      sig { params(field_tree: FieldTree, current_query: GraphQL::Query).void }
      def track_query_node_count_breakdowns(field_tree, current_query)
        node_count_breakdowns = current_query.context[:node_count_breakdowns] = []
        field_tree.roots.each do |node|
          node_count_breakdowns.concat(node.field.max_node_count_breakdowns)
        end
      end

      sig { params(field_tree: FieldTree, current_query: GraphQL::Query).void }
      def track_query_cost_breakdowns(field_tree, current_query)
        cost_breakdowns = current_query.context[:cost_breakdowns] = []
        field_tree.roots.each do |node|
          cost_breakdowns.concat(node.field.max_request_count_breakdowns)
        end
      end

      sig { params(visitor: T.nilable(GraphQL::Analysis::AST::Visitor)).returns(T.nilable(GraphQL::Query)) }
      def get_current_query(visitor)
        current_query = T.let(nil, T.nilable(GraphQL::Query))
        if query.nil?
          # If the analyzer's query field is nil, we are in a multiplex and need to get the query from the visitor.
          if visitor.nil?
            # This  scenario isn't expected to happen.
            return nil
          end
          current_query = T.let(visitor.query, GraphQL::Query)
        else
          current_query = T.must(query)
        end
        current_query
      end

      sig { params(query_tracker: Platform::QueryTracker, potential_query_scores: Platform::Analyzers::QueryCoster::PotentialQueryCosts).void }
      def track_potential_query_scores(query_tracker, potential_query_scores)
        # Log each potential query score to Datadog.
        potential_query_scores.to_hash.each do |key, value|
          if value.nil?
            next
          end

          # If the value is a boolean, we need to convert it to a number
          if [true, false].include?(value)
            value = value ? 1 : 0
          end

          GitHub.dogstats.histogram("platform.analyzers.calculate_query_cost.potential_query_cost.#{key}", value, tags: query_tracker.dog_tags)
        end

        # Add the potential costs to the query context so they can be logged to Hydro.
        query_tracker.potential_query_costs = potential_query_scores
      end

      # Private: Find how many nodes have been requested for a field.
      # Returns number if limit is present, nil otherwise.
      sig { params(ast_node: GraphQL::Language::Nodes::Field, visitor: GraphQL::Analysis::AST::Visitor).returns(T.nilable(Integer)) }
      def find_requested_nodes_count(ast_node, visitor)
        if @count_list_complexity
          find_requested_nodes_count_with_list_complexity(ast_node, visitor)
        else
          find_requested_nodes_count_without_list_complexity(ast_node, visitor)
        end
      end

      # Private: Find how many nodes have been requested for a field, taking lists into account.
      # If the field is a non-paginated list, we'll return the list node count.
      # If the field is paginated, we'll return the pagination node count (as that's the true number of nodes requested).
      # If the field is not a list or paginated, we'll return `nil`.
      sig { params(ast_node: GraphQL::Language::Nodes::Field, visitor: GraphQL::Analysis::AST::Visitor).returns(T.nilable(Integer)) }
      def find_requested_nodes_count_with_list_complexity(ast_node, visitor)
        field_definition = T.let(visitor.field_definition, T.nilable(GraphQL::Schema::Field))
        # field_defn shouldn't be nil as we've entered a field, but visitor.field_definition
        # is defined as nilable, so we should check it's not nil to appease Sorbet.
        return if field_definition.nil?

        list_node_count = get_field_list_node_count(ast_node, visitor)
        count = list_node_count if list_node_count

        # If the field is paginated, we want to get the count of requested nodes.
        # It's possible for a list field to also be paginated (i.e. a list with `first`, `last`, or `ids` arguments).
        # In that case, we want to use the pagination count, as that's the true number of nodes requested.
        pagination_node_count = get_field_pagination_node_count(ast_node, visitor)
        # We're only interested in the field node count if it isn't nil, as for lists it'll override the list node count retrieved above.
        count = pagination_node_count if pagination_node_count
        count
      end

      # Private: Find how many nodes have been requested for a field, assuming list complexity is not enabled.
      sig { params(ast_node: GraphQL::Language::Nodes::Field, visitor: GraphQL::Analysis::AST::Visitor).returns(T.nilable(Integer)) }
      def find_requested_nodes_count_without_list_complexity(ast_node, visitor)
        get_field_pagination_node_count(ast_node, visitor)
      end

      # Calculates the query cost score by dividing the total request count by 100 and rounding to the nearest whole number,
      # as described in our public docs here: https://docs.github.com/en/graphql/overview/rate-limits-and-node-limits-for-the-graphql-api#predicting-the-point-value-of-a-query
      sig { params(request_count: Integer).returns(Integer) }
      def calculate_query_cost_score(request_count)
        [(request_count / 100.0).round, 1].max
      end

      sig { params(schema_parent_type: GraphQLMemberOrInterface, parent_field: T.nilable(Field), current_query: GraphQL::Query).returns(T::Array[GraphQLMemberOrInterface]) }
      def find_possible_types_with_corrected_branch_detection(schema_parent_type, parent_field, current_query)
        possible_types = T.let([], T::Array[GraphQLMemberOrInterface])
        # This branch does essentially the same as the one below, with one modification:
        # when the fields are nested, we need to attach it not to parent based on schema, but to the parent that is in the tree for query cost calculation.
        # That prevents incorrect detection of typed children and therefore incorrect branch cost calculation.
        # It's a fix for https://github.com/github/graphql-platform/issues/853.
        # analyzer_parent_type is either schema parent type for a root field, or type of the last field in the tree.
        if parent_field
          # Note: parent_field.field_defn.type.unwrap provides the same value for the parent type as visitor.parent_type_definition,
          # or accessing visitor.type_definition when we've entered that field. parent_field.field_defn.type.unwrap allows us to access
          # that value without the visitor.
          analyzer_parent_type = T.cast(parent_field.field_defn.type.unwrap, GraphQLMemberOrInterface)
        else
          analyzer_parent_type = schema_parent_type
        end

        # if the type of the last field in the tree is abstract, we need to calculate the possible types for it based on schema.
        possible_types = if T.unsafe(analyzer_parent_type).kind.abstract?
          T.cast(current_query.possible_types(schema_parent_type), T::Array[GraphQLMemberOrInterface])
        else
          # otherwise, we want to attach node directly to this type.
          [analyzer_parent_type]
        end
        possible_types
      end

      sig { params(schema_parent_type: GraphQLMemberOrInterface, parent_field: T.nilable(Field), current_query: GraphQL::Query).returns(T::Array[GraphQLMemberOrInterface]) }
      def find_possible_types(schema_parent_type, parent_field, current_query)
        possible_types = T.let([], T::Array[GraphQLMemberOrInterface])
        if @corrected_branch_detection
          possible_types = find_possible_types_with_corrected_branch_detection(schema_parent_type, parent_field, current_query)
        else
          possible_types = if T.unsafe(schema_parent_type).kind.abstract?
            T.cast(current_query.possible_types(schema_parent_type), T::Array[GraphQLMemberOrInterface])
          else
            [schema_parent_type]
          end
        end
        possible_types
      end

      # Private: Get the count of requested nodes for a list field.
      # If the field is a list, we'll return either a custom count or a default value if a custom count isn't provided.
      # If the field is not a list, we'll return `nil`.
      sig { params(ast_node: GraphQL::Language::Nodes::Field, visitor: GraphQL::Analysis::AST::Visitor).returns(T.nilable(Integer)) }
      def get_field_list_node_count(ast_node, visitor)
        field_definition = T.let(visitor.field_definition, T.nilable(GraphQL::Schema::Field))
        # field_defn shouldn't be nil as we've entered a field, but visitor.field_definition
        # is defined as nilable, so we should check it's not nil to appease Sorbet.
        return if field_definition.nil?
        count = T.let(nil, T.nilable(Integer))
        field_name = T.let(ast_node.name, String)
        # If the field is a list, we want to get the complexity from the field definition
        # this filters out nodes + edges & internal ratelimiting breakdown list fields from getting lists complexities
        if field_definition.type.list? && !%w[nodes edges costBreakdowns nodeCountBreakdowns].include?(field_name)
          # Note: it looks like field_definition.complexity can also return a Proc, so we need to handle that scenario.
          field_definition_complexity = if field_definition.complexity.is_a?(Proc)
            field_definition.complexity.call
          else
            field_definition.complexity
          end

          # default complexity for fields is 1: https://graphql-ruby.org/api-doc/1.8.13/GraphQL/Field.html#complexity-instance_method.
          # but we want default Lists complexity to be Platform::DEFAULT_LIST_COST, or another custom one, but not 1.
          count = field_definition_complexity == 1 ? Platform::DEFAULT_LIST_COST : field_definition_complexity
        end
        count
      end

      # Private: Get the count of requested nodes for a paginated field.
      # A paginated field is one that has `first`, `last`, or `ids` arguments.
      # For all other fields, this will return `nil`.
      sig { params(ast_node: GraphQL::Language::Nodes::Field, visitor: GraphQL::Analysis::AST::Visitor).returns(T.nilable(Integer)) }
      def get_field_pagination_node_count(ast_node, visitor)
        field_definition = T.let(visitor.field_definition, T.nilable(GraphQL::Schema::Field))
        count = T.let(nil, T.nilable(Integer))
        arguments = T.let(
          visitor.arguments_for(ast_node, field_definition),
          T.any(
            GraphQL::Execution::Interpreter::Arguments,
            GraphQL::Schema::Validator::ValidationFailedError, # Note: this return type has been observed in the CI tests, but is not documented.
            GraphQL::Execution::Lazy)) # Note: this return type has been observed in the CI tests, but is not documented.
        if arguments.is_a?(GraphQL::Execution::Interpreter::Arguments)
          count = T.let((arguments[:first] || arguments[:last] || arguments[:ids]&.length), T.nilable(Integer))
        end
        count
      end

      # This type alias is used for ensuring type safety of any values which are expected to represent the type of a GraphQL object or interface.
      GraphQLMemberOrInterface = T.type_alias { T.any(T::Class[GraphQL::Schema::Member], T::Class[GraphQL::Schema::Interface], Module) }
    end
  end
end
