# typed: true
# frozen_string_literal: true

module Platform
  module Tracing
    module MapToService
      include DefaultTracerBase
      def platform_execute
        super
      end

      def execute_field(field:, query:, ast_node:, arguments:, object:)
        GitHub::ServiceMapping.push_graphql_service_mapping_context(field, query.context) do
          set_current_root_field_catalog_service(field, query)
          super
        end
      end

      def execute_field_lazy(field:, query:, ast_node:, arguments:, object:)
        GitHub::ServiceMapping.push_graphql_service_mapping_context(field, query.context) do
          with_current_root_field_catalog_service(field, query) do
            super # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end
        end
      end

      def authorized(query:, type:, object:)
        GitHub::ServiceMapping.push_graphql_service_mapping_context(type, query.context) do
          super
        end
      end

      def authorized_lazy(query:, type:, object:)
        GitHub::ServiceMapping.push_graphql_service_mapping_context(type, query.context) do
          super # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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

      # Sets `current_root_field_catalog_service` on the query context to the catalog
      # service that owns the given root field, so that errors during execution are
      # attributed to the root field's owning service rather than to whatever nested
      # type happens to be resolving when the error occurs.
      #
      # No-op when the FF is disabled, when `field` is not a root field, or when no
      # specific service can be determined (we don't want to clobber a more-specific
      # service set by a nested resolver/loader with `:unknown`).
      def set_current_root_field_catalog_service(field, query)
        return unless root_field_attribution_enabled?
        return unless %w[Mutation Query Subscription].include?(field.owner.graphql_name)

        root_service = field.service_mapping
        # Fall back to the unwrapped return type when the field itself has no explicit
        # mapping (e.g. a Mutation root field whose payload type is wrapped in NonNull
        # doesn't `respond_to?(:service_mapping)` until unwrapped).
        if (root_service.nil? || root_service == :unknown) && field.type.respond_to?(:unwrap)
          unwrapped = field.type.unwrap
          if unwrapped.respond_to?(:service_mapping)
            unwrapped_service = unwrapped.service_mapping
            root_service = unwrapped_service if unwrapped_service && unwrapped_service != :unknown
          end
        end

        return unless root_service && root_service != :unknown

        query.context[:current_root_field_catalog_service] =
          GitHub::ServiceMapping.catalog_service_name(root_service)
      end

      # Variant of `set_current_root_field_catalog_service` that saves and restores the
      # previous value around the block. Used in `execute_field_lazy` so that a lazy
      # batch resolving a different root field doesn't leak its attribution into the
      # subsequent lazy resolution of an earlier root field.
      def with_current_root_field_catalog_service(field, query)
        return yield unless root_field_attribution_enabled?

        context = query.context
        had_previous_root_service = context.key?(:current_root_field_catalog_service)
        previous_root_service = context[:current_root_field_catalog_service]

        set_current_root_field_catalog_service(field, query)

        begin
          yield
        ensure
          if had_previous_root_service
            context[:current_root_field_catalog_service] = previous_root_service
          else
            context.delete(:current_root_field_catalog_service)
          end
        end
      end

      # Pass this instead of a type or field when tracing top-level events
      class GraphQLServiceSingleton
        def self.service_mapping
          :graphql_api
        end
      end

      private

      # Memoized per trace instance (one per query/multiplex) so a flag flip mid-query
      # can't cause `with_current_root_field_catalog_service` to take the early-return
      # path on entry but the full save/restore path on exit (or vice versa).
      def root_field_attribution_enabled? # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
        return @root_field_attribution_enabled if defined?(@root_field_attribution_enabled)
        @root_field_attribution_enabled =
          FeatureFlag.vexi.enabled?(:graphql_platform_root_field_service_attribution, default: false)
      end
    end
  end
end
