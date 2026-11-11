# typed: strict
# frozen_string_literal: true

# This interface defines the contract for serializing field values into structured representations
# that can be consumed by various APIs and export mechanisms.
module MemexProjectColumn::Interface::Serializable
  module WebApi
    extend T::Helpers
    abstract!

    requires_ancestor { MemexProjectColumn::Field::Base }

    module ClassMethods
      extend T::Helpers
      abstract!

      # Returns true if the field can safely be serialized (because it fully implements all the abstract methods of
      # this interface), false otherwise.
      sig { abstract.returns(T::Boolean) }
      def web_api_serializable?; end

      # Whether or not we need to preload the `content`, `repository` and `content.repository` associations
      # of each item before attempting further preloading or serialization specific to this field type.
      #
      # This should return true if this field type will use some attribute of the item's content or repository during
      # serialization (e.g. it will serialize a URL that contains the repository full name).
      sig { abstract.returns(T::Boolean) }
      def should_preload_content_tree?; end
    end

    mixes_in_class_methods(ClassMethods)

    ValueReturn = T.type_alias do
      T.any(
        MemexProjectColumnValue::SerializableValue,
        T::Array[MemexProjectColumnValue::SerializableValue]
      )
    end

    # Returns a structured representation of the field's value, typically for internal usage.
    sig do
      abstract.
        params(
          item: MemexProjectItem,
          prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
          redacted_issue_ids: T::Array[Integer],
        ).
        returns(T.nilable(ValueReturn))
    end
    def value(item, prefilled_associations: nil, redacted_issue_ids: []); end

    sig { returns(T.untyped) }
    attr_accessor :preloaded_web_api_response_data

    # Whether or not we've preloaded data such that we can serialize this field type without issuing any
    # additional SQL queries.
    sig { returns(T::Boolean) }
    def preloaded_web_api_response_data?
      @preloaded_web_api_response_data.present?
    end

    # Public interface method that calls the internal hook for preloading response data and caches the result.
    #
    # We define this external method so that implementors are only responsible for implementing the internal hook
    # that has a clearer interface. Without this, implementors would have to set the
    # `@preloaded_web_api_response_data` instance variable themselves, which is a difficult requirement to enforce.
    sig { params(items: T::Array[MemexProjectItem], fields: T::Array[MemexProjectColumn::Field::Base]).void }
    def preload_web_api_response_data!(items:, fields:)
      preloaded_data = preload_web_api_response_data(items:, fields:)
      self.preloaded_web_api_response_data = preloaded_data unless preloaded_data.nil?
    end

    # Preloads data required for serializing API responses without issuing any additional SQL queries.
    #
    # This is the internal (private) hook that must be implemented by each Field subclass that implements this
    # interface.
    #
    # @param items The set of items that we should preload field data for (which is the same set of items that we
    #   will ultimately serialize)
    # @param fields The full set of fields that we intend to serialize. This is provided to allow fields that share
    #   a base class or a helper interface to perform preloading once for all subclasses if possible.
    #
    # @returns Map from project item ID to the appropriate `MemexProjectColumnValue::SerializableValue` for this
    #   field type.
    sig do
      abstract
        .params(items: T::Array[MemexProjectItem], fields: T::Array[MemexProjectColumn::Field::Base])
        .returns(T.nilable(T::Hash[Integer, T.untyped]))
    end
    private def preload_web_api_response_data(items:, fields:); end
  end
end
