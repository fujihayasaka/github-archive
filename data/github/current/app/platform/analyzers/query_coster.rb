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
        @field_tree_builder_with_corrected_parent_request_count = T.let(FieldTreeBuilder.new, FieldTreeBuilder)
        @rate_limit_check_start = T.let(0, Numeric) # This will be set in `analyze?` method as the Visitor starts.

        # Evaluate all feature flags before any calculations
        if analyze?
          actor = T.let(subject.context[:actor], T.untyped)
          oauth_app = T.let(subject.context[:oauth_app], T.untyped)
          integration = T.let(subject.context[:integration], T.untyped)

          @bypass_query_coster_parent_request_count_changes = T.let(feature_flag_enabled?(:graphql_bypass_query_coster_parent_request_count_changes, actor, oauth_app, integration), T::Boolean)
          @corrected_parent_request_count_enabled = T.let(@bypass_query_coster_parent_request_count_changes ? false : feature_flag_enabled?(:graphql_corrected_parent_request_count, actor, oauth_app, integration), T::Boolean)

          @track_potential_query_costs = T.let(feature_flag_enabled?(:graphql_track_potential_query_costs, actor, oauth_app, integration), T::Boolean)
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

        # This is the start time for the rate limit check, which will be used later to measure the duration of the cost calculation.
        # This must be set in analyze? due to 'on_enter_document' is never invoked
        @rate_limit_check_start = GitHub::Dogstats.monotonic_time

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

        # This is used for checking whether the current field is a composite type (i.e. an object, interface, or union).
        # We use this to determine whether we should add the field to the tree, as it's possible that one of its children will be a field we can calculate a cost of
        # (i.e. one of its children is a connection field)
        is_composite = T.let(field_defn.type.kind.composite?, T::Boolean)

        # if current field is a field we can calculate a cost of, or if it's a first field of the query, we want to add it to the tree.
        if requested_nodes_count.present? || @field_tree_builder.active_field.nil? || is_composite
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
          # This is temporary code for tracking the potential query costs for corrected request count calculations.
          # It'll be removed once the graphql_corrected_parent_request_count feature flag is removed.
          if requested_nodes_count.present? || @field_tree_builder_with_corrected_parent_request_count.active_field.nil? || is_composite
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
        field_defn = T.let(visitor.field_definition, T.nilable(GraphQL::Schema::Field))
        # field_defn shouldn't be nil as we've left a field, but visitor.field_definition
        # is defined as nilable, so we should check it's not nil to appease Sorbet.
        return if field_defn.nil?

        is_composite = T.let(field_defn.type.kind.composite?, T::Boolean)

        if count.present? || is_composite
          @field_tree_builder.exit_field
        end

        if @track_potential_query_costs
          if count.present? || is_composite
            @field_tree_builder_with_corrected_parent_request_count.exit_field
          end
        end
      end

      # Hack: Treat inline fragments as fields for cost analysis by entering/exiting the builder with a 'field' created from the inline fragment node.
      # This is a temporary solution to allow us to track inline fragments in the query cost calculations, by retrofitting it into the existing field tree builder logic.
      # The intention is to clean this up in the future.
      sig { override.params(node: GraphQL::Language::Nodes::InlineFragment, parent: T.nilable(GraphQL::Language::Nodes::AbstractNode), visitor: GraphQL::Analysis::AST::Visitor).void }
      def on_enter_inline_fragment(node, parent, visitor)
        return if visitor.skipping?

        # Get the current query which owns the entered fragment.
        current_query = get_current_query(visitor)
        return if current_query.nil?

        # The type condition for the fragment, or fallback to parent type.
        parent_field = @field_tree_builder.active_field
        schema_parent_type = node.type ? current_query.schema.types[node.type.name] : (parent_field&.field_defn&.type&.unwrap)
        possible_types = find_possible_types(schema_parent_type, parent_field, current_query)

        # Grab the schema definition of the current field.
        field_defn = T.let(visitor.field_definition, T.nilable(GraphQL::Schema::Field))

        return if field_defn.nil?

        # Create a fake 'field' for the inline fragment.
        field = Field.new(
          1, # Inline fragments are treated as having a value of 1, to get around the current logic for fields which requires a value.
          ast_node: node,
          parent: parent_field,
          schema_parent_type: schema_parent_type,
          possible_types: possible_types,
          field_defn: field_defn,
          corrected_parent_request_count_enabled: @corrected_parent_request_count_enabled
        )
        @field_tree_builder.enter_field(field)

        if @track_potential_query_costs
          # Create a fake 'field' for the inline fragment for the corrected parent request count tree builder.
          field = Field.new(
            1, # Inline fragments are treated as having a value of 1, to get around the current logic for fields which requires a value.
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

      sig { override.params(node: GraphQL::Language::Nodes::InlineFragment, parent: T.nilable(GraphQL::Language::Nodes::AbstractNode), visitor: GraphQL::Analysis::AST::Visitor).void }
      def on_leave_inline_fragment(node, parent, visitor)
        return if visitor.skipping?

        @field_tree_builder.exit_field

        if @track_potential_query_costs
          @field_tree_builder_with_corrected_parent_request_count.exit_field
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
        err = validate_query_field_tree(field_tree, current_query)

        #Emit our timer before returning the possible error from validation
        GitHub.dogstats.distribution_timing_since("platform.analyzers.calculate_query_cost.duration", @rate_limit_check_start, tags: current_query.context[:query_tracker].dog_tags)

        err
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
        query_cost_score = calculate_query_cost_score(field_tree.total_request_count)
        track_query_cost_score(query_cost_score, current_query)

        track_query_node_count_breakdowns(field_tree, current_query)
        total_node_count = field_tree.total_node_count
        track_query_total_node_count(total_node_count, current_query)

        total_request_count = field_tree.total_request_count
        current_query.context[:request_count_total] = total_request_count
      end

      sig { params(field_tree: FieldTree, current_query: GraphQL::Query).returns(T.nilable(GraphQL::AnalysisError)) }
      def validate_query_field_tree(field_tree, current_query)
        total_node_count = field_tree.total_node_count
        # If we were over the node limit, find the first field which broke the node limit
        # and report it to client, preventing execution.
        node_limit = get_node_limit(current_query)
        if total_node_count > node_limit
          first_exceeding_node = field_tree.find_first_node_count_exceeding(node_limit)
          return Platform::Errors::MaxNodeLimitExceeded.new(total_node_count: total_node_count, limit: node_limit, node: first_exceeding_node)
        end

        if GitHub.rate_limiting_enabled? && cost_limiter = current_query.context[:cost_limiter]
          if !current_query.context[:query_tracker].rate_limit_request_query?
            at_rate_limit = cost_limiter.should_limit(
              current_query.context[:query_tracker].query_cost
            )
            if at_rate_limit
              current_query.context[:query_tracker].rate_limited!
              blocked_from = "after_query_evaluation"
              GitHub.dogstats.increment("platform.analyzers.rate_limit_request_query.rate_limited", tags: ["blocked_from:#{blocked_from}"])
              type, id = cost_limiter.configuration.key.split("-")
              Platform::Errors::RateLimited.new("API rate limit exceeded for #{type} ID #{id}.")
            end
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
        potential_parent_request_count = nil
        if !@corrected_parent_request_count_enabled
          # Build the final field tree from the corrected parent request count builder.
          field_tree_with_corrected_parent_request_count = @field_tree_builder_with_corrected_parent_request_count.build
          potential_parent_request_count = field_tree_with_corrected_parent_request_count.total_request_count
        end

        potential_query_scores = PotentialQueryCosts.new(
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
        get_field_pagination_node_count(ast_node, visitor)
      end

      # Calculates the query cost score by dividing the total request count by 100 and rounding to the nearest whole number,
      # as described in our public docs here: https://docs.github.com/en/graphql/overview/rate-limits-and-node-limits-for-the-graphql-api#predicting-the-point-value-of-a-query
      sig { params(request_count: Integer).returns(Integer) }
      def calculate_query_cost_score(request_count)
        [(request_count / 100.0).round, 1].max
      end

      sig { params(schema_parent_type: GraphQLMemberOrInterface, parent_field: T.nilable(Field), current_query: GraphQL::Query).returns(T::Array[GraphQLMemberOrInterface]) }
      def find_possible_types(schema_parent_type, parent_field, current_query)
        possible_types = T.let([], T::Array[GraphQLMemberOrInterface])
        possible_types = if T.unsafe(schema_parent_type).kind.abstract?
          T.cast(current_query.possible_types(schema_parent_type), T::Array[GraphQLMemberOrInterface])
        else
          [schema_parent_type]
        end
        possible_types
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
            GraphQL::Execution::Lazy, # Note: this return type has been observed in the CI tests, but is not documented.
            Platform::Errors::NotFound)) # Observed in production (https://github.sentry.io/issues/6566551727?project=1885898)
        if arguments.is_a?(GraphQL::Execution::Interpreter::Arguments)
          count = T.let((arguments[:first] || arguments[:last] || arguments[:ids]&.length), T.nilable(Integer))
        end
        count
      end

      # Private: Evaluate feature flags for the user and their OAuth app / app integration.
      # Returns a Boolean indicating if the feature flag is enabled for any of the contexts.
      sig { params(flag_name: Symbol, actor: T.untyped, oauth_app: T.untyped, integration: T.untyped).returns(T::Boolean) }
      def feature_flag_enabled?(flag_name, actor, oauth_app, integration)
        # Start with the basic actor check (maintains backward compatibility)
        return true if FeatureFlag.vexi.enabled?(flag_name, actor, default: false)

        app = oauth_app || integration
        return false unless app

        FeatureFlag.vexi.enabled?(flag_name, app, default: false)
      end

      # This type alias is used for ensuring type safety of any values which are expected to represent the type of a GraphQL object or interface.
      GraphQLMemberOrInterface = T.type_alias { T.any(T::Class[GraphQL::Schema::Member], T::Class[GraphQL::Schema::Interface], Module) }
    end
  end
end
