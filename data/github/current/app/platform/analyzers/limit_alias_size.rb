# typed: true
# frozen_string_literal: true


module Platform
  module Analyzers
    # This analyzer limits the character count of an alias in a GraphQL query.
    # Without this check, a DoS attack could be performed by crafting very large aliases that are repeated
    # many times in the response.
    #
    # For example, if a query retrieves a list of users in an organization,
    # and each user is aliased with a 1MB long string, and the organization has 1000 users, then the
    # response will be roughly 1GB (1000 * 1MB).
    class LimitAliasSize < GraphQL::Analysis::AST::Analyzer
      def initialize(query)
        super

        @failing_node = nil
        @enabled = analyze? && ::FeatureFlag.vexi.enabled?(:graphql_limit_alias_size, default: false)
        @length_of_largest_alias = 0
      end

      # Run this analyzer when any of these conditions is true:
      # - Internal query analysis is enabled
      # - The current target isn't `:internal`
      def analyze?
        GitHub.analyze_internal_graphql? || query.context[:target] != :internal
      end

      def on_enter_field(node, parent, visitor)
        alias_size = node.alias&.size || 0
        @length_of_largest_alias = [alias_size, @length_of_largest_alias].max

        if alias_size > Platform.max_alias_size
          @failing_node = node
        end

      end

      def result
        query.context[:query_tracker].length_of_largest_alias = @length_of_largest_alias

        if !@failing_node.nil?
          Platform::Errors::MaxAliasSizeExceeded.new("alias exceeds #{Platform.max_alias_size} character limit: #{@failing_node.alias}", ast_node: @failing_node)
        end
      end
    end
  end
end
