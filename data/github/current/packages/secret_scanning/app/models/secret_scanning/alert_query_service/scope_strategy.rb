# typed: true
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecretScanning
  class AlertQueryService
    ##
    # Abstract class for defining scope-specific behavior for `AlertQueryService`
    class ScopeStrategy
      extend T::Helpers
      include GitHub::Memoizer
      include GitHub::SecurityCenter::LoggingHelper

      abstract!

      ##
      # Apply the scope-specific selector to the request hash. Handles any user-supplied filters as pertaining to that
      # scope. Modifies the request hash in place.
      #
      # @param request_hash [Hash] the builder used as input to the underlying proto request object
      # @param aggregation_filter [String, nil] one of the filter types defined by `GroupByAggregation`
      sig do
        abstract.params(
          request_hash: T::Hash[Symbol, T.untyped],
          aggregation_filter: T.nilable(String)
        ).void
      end
      def with_selector!(request_hash, aggregation_filter:) end

      sig { abstract.params(request_hash: T::Hash[Symbol, T.untyped]).void }
      def with_feature_flags!(request_hash) end

      ##
      # Create a scope object used for post-filtering results by tenant.
      #
      sig { abstract.returns(GitHub::SecurityCenter::TenantFilteringHelper::RequestScope) }
      def tenant_filter_scope() end

      # TODO: What do we do about this abstract method not being implemented in the Repo scope strategy?
      ##
      # Map the aggregation results from backend service into a format that can be used by frontend.
      #
      # @param filter [String] one of the filter types defined by `GroupByAggregation`
      # @param aggregation the aggregation object returned from the backend service
      # @return [Array<Array<Hash>, Boolean>] an array of option groups and a boolean indicating backed request success
      #   The first element follows the structure
      #     [
      #       {
      #         title: "Group Label", # optional, typically only used when multiple groups are returned
      #         items: [
      #           {
      #             label: "Item Label",
      #             description: "Item description", # optional secondary text
      #             count: 99,
      #             slug: "item-url-slug"
      #           }
      #         ]
      #       },
      #       ...
      #     ]
      # sig do
      #   abstract.params(
      #     filter: String,
      #     aggregation: T.untyped,
      #   ).returns([
      #     T::Array[T::Hash[Symbol, T.untyped]],
      #     T::Boolean,
      #   ])
      # end
      def map_filter_options(filter, aggregation)
        # must override in concrete classes
        raise NotImplementedError
      end

      ##
      # Indicates whether custom patterns are supported by the tenant
      sig { abstract.returns(T::Boolean) }
      def show_custom_patterns?() end
    end
  end
end
