# typed: true
# frozen_string_literal: true

module Platform
  module Tracing
    module MapToService
      def platform_execute
        yield
      end

      def execute_field(field:, query:, ast_node:, arguments:, object:)
        GitHub::ServiceMapping.push_graphql_service_mapping_context(field, query.context) do
          super
        end
      end

      def execute_field_lazy(field:, query:, ast_node:, arguments:, object:)
        GitHub::ServiceMapping.push_graphql_service_mapping_context(field, query.context) do
          super
        end
      end

      def authorized(query:, type:, object:)
        GitHub::ServiceMapping.push_graphql_service_mapping_context(type, query.context) do
          super
        end
      end

      def authorized_lazy(query:, type:, object:)
        GitHub::ServiceMapping.push_graphql_service_mapping_context(type, query.context) do
          super
        end
      end

      def resolve_type(query:, type:, object:)
        GitHub::ServiceMapping.push_graphql_service_mapping_context(type, query.context) do
          super
        end
      end

      def resolve_type_lazy(query:, type:, object:)
        GitHub::ServiceMapping.push_graphql_service_mapping_context(type, query.context) do
          super
        end
      end

      def analyze_multiplex(multiplex:)
        multiplex.queries.each do |query|
          GitHub::ServiceMapping.push_graphql_service_mapping_context(GraphQLServiceSingleton, query.context) do
            super
          end
        end
      end

      # Pass this instead of a type or field when tracing top-level events
      class GraphQLServiceSingleton
        def self.service_mapping
          :graphql_api
        end
      end
    end
  end
end
