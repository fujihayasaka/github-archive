# typed: strict
# frozen_string_literal: true

# This interface defines the contract for serializing field values into structured representations
# that can be consumed by various APIs and export mechanisms.
#
# Rather than including this module directly, most consumers will inherit this interface via
# `MemexProjectColumn::Field::Base`, which is the base class for all fields.
#
# To properly implement this interface, subclasses must define:
#
# 2. `value` method:
#    Returns the appropriate `MemexProjectColumnValue::*` typed struct that implements the
#    `MemexProjectColumnValue::SerializableValue` interface for the field's value.
#
# 3. `web_api_serializable?` class method:
#    Returns true if the above methods have been implemented correctly and the field should
#    be considered safe for serialization.
module MemexProjectColumn::Interface::Serializable
  module WebApi
    extend T::Helpers
    interface!

    module ClassMethods
      extend T::Helpers
      abstract!

      # Returns true if the field can safely be serialized, false otherwise.
      sig { abstract.returns(T::Boolean) }
      def web_api_serializable?; end
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

    # Preloads data required for efficient API response generation.
    #
    # This method is called by `MemexProject#preload_web_api_response_data` to batch-load
    # related records that will be needed when serializing field values. By preloading
    # associations upfront, we avoid N+1 query problems when generating API responses
    # for multiple project items.
    #
    # Subclasses should override this method to preload any ActiveRecord associations
    # or other data sources that `value` methods depend on.
    sig { abstract.params(items: T::Array[MemexProjectItem]).void }
    def preload_web_api_response_data(items); end
  end
end
