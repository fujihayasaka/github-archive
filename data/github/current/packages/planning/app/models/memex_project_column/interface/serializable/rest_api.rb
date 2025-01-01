# typed: strict
# frozen_string_literal: true

# This interface provides REST API-specific serialization capabilities for field values.
# It enables implementers to create standardized hash representations suitable for
# consumption by external REST API clients.
#
# This interface should be included by all field classes that need to expose their data
# via the REST API.
#
# To properly implement this interface, subclasses must:
#
# 1. Define the `to_rest_api_hash` method to transform the output of `serializable`
#    into a REST API-appropriate format
# 2. Implement the `rest_api_serializable?` predicate method to indicate that the
#    field is ready for REST API serialization
module MemexProjectColumn::Interface::Serializable
  module RestApi
    extend T::Helpers
    interface!

    module ClassMethods
      extend T::Helpers
      abstract!

      # Class method interface to indicate if this field type supports REST API serialization.
      # This provides a consistent way to check if a field can be safely exposed via REST API
      # without needing to instantiate the field or attempt serialization.
      #
      # Subclasses should override this to return true if they implement proper REST API serialization.
      sig { abstract.returns(T::Boolean) }
      def rest_api_serializable?; end
    end

    mixes_in_class_methods(ClassMethods)

    # Complete return type for REST API serialization - can be a hash, array, scalar, or nil
    RestApiSerializedValue = T.type_alias do
      T.any(
        T::Hash[T.any(String, Symbol), T.untyped],
        T::Array[T.untyped],
        String,
        Integer,
        Numeric,
        T::Boolean
      )
    end

    # Returns a hash representation of the field value suitable for REST API consumption.
    #
    # This method should transform the output from the `serializable` method into a standardized
    # format that external API implementations can reliably consume. Typically, this means leveraging
    # serializers defined in the Api::Serializer module, but for simple cases, it may be sufficient
    # to return a scalar value directly.
    #
    # ## Note:
    #
    # This method is not optimally supported with the item prefiller in all cases as
    # the prefiller doesn't preload all associations needed for REST API serialization.
    # To ensure we don't query for more data than necessary in the majority of cases,
    # it is recommended to use `preload_rest_api_response_data` on `MemexProject` instead.
    #
    # ## Example:
    #
    # ```ruby
    # MemexProjectColumn::Interface::Serializable::RestApi.preload_rest_api_response_data(
    #   project:
    #   items:,
    #   fields:,
    # )
    #
    # columns.map |c| do
    #   field = c.to_field
    #   field.to_rest_api_hash(item)
    # end
    # ```
    sig do
      abstract.
        params(
          item: MemexProjectItem,
          redacted_issue_ids: T::Array[Integer],
        ).
        returns(T.nilable(RestApiSerializedValue))
    end
    def to_rest_api_hash(item, redacted_issue_ids: []); end

    # Preloads data required for efficient REST API response generation.
    #
    # This method is called by `MemexProject#preload_rest_api_response_data` to batch-load
    # related records that will be needed when serializing field values. By preloading
    # associations upfront, we avoid N+1 query problems when generating REST API responses
    # for multiple project items.
    #
    # Subclasses should override this method to preload any ActiveRecord associations
    # or other data sources that their `to_rest_api_hash` methods depend on.
    sig { abstract.params(items: T::Array[MemexProjectItem]).void }
    def preload_rest_api_response_data(items); end
  end
end
