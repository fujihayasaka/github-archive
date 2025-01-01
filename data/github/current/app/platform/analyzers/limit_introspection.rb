# typed: true
# frozen_string_literal: true

module Platform
  module Analyzers
    # Since introspection fields don't use `first`/`last` for pagination,
    # they aren't covered by our rate limiting code.
    #
    # Let's manually limit access to introspection data so that
    # people don't swamp us with convoluted introspection requests!
    class LimitIntrospection < GraphQL::Analysis::AST::Analyzer
      # List fields under __schema are only allowed this many times in a query:
      MAX_INTROSPECTION_FIELD_USAGES = 2

      def initialize(*)
        super
        # Make a place to track where introspection fields are used
        # { String => count of field usages }
        @list_field_usages = Hash.new(0)
      end

      # Run this analyzer for all external queries,
      # but for internal queries, only run it if explicitly enabled
      def analyze?
        if query.context[:origin] == Platform::ORIGIN_INTERNAL
          GitHub.analyze_internal_graphql?
        else
          if query.context[:operation_id].present?
            return GitHub.flipper[:gql_run_analyzers_on_persisted_queries].enabled?
          end
          true
        end
      end

      # Limit introspection fields which return lists of introspection values
      def on_enter_field(node, parent, visitor)
        parent_type = visitor.parent_type_definition
        return_type = visitor.field_definition.type

        if parent_type.introspection? && list_type_at_all?(return_type)
          field_name = "#{parent_type.graphql_name}.#{node.name}"
          @list_field_usages[field_name] += 1
        end
      end

      # If there are more than the allowed number of usages, return an error
      def result
        overused_fields = {}
        @list_field_usages.each do |field, count|
          if count > MAX_INTROSPECTION_FIELD_USAGES
            overused_fields[field] = count
          end
        end


        if overused_fields.any?
          Platform::Errors::IntrospectionLimitExceeded.new(
            overused_fields,
            MAX_INTROSPECTION_FIELD_USAGES,
          )
        else
          # Nothing to report, a valid query.
          nil
        end
      end

      private

      # Return true if this type is a list type at any level (any nullability)
      def list_type_at_all?(type)
        if type.kind.non_null?
          list_type_at_all?(type.of_type)
        elsif type.kind.list?
          true
        else
          false
        end
      end
    end
  end
end
