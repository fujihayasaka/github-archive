# typed: strict
# frozen_string_literal: true

module CustomPropertiesCore
  module IValuesManager
    extend T::Helpers

    include Kernel
    # remove this include once CustomPropertiesCore migration is done
    include CustomProperties
    include CustomPropertiesCore::Errors

    interface!

    sig do
      abstract.params(
        targets: T::Array[IPropertyTarget],
        properties: T::Hash[String, PropertyValue],
      ).void
    end
    def set_properties_for(targets, properties); end

    sig do
      abstract.params(
        property_name: String,
        search_term: String,
        limit: T.nilable(Integer)
      ).returns(T::Array[String])
    end
    def search_property_values(property_name, search_term, limit: nil); end

    sig do
      abstract.params(
        properties: T::Hash[T.any(String, Symbol), PropertyValue]
      ).returns(T::Array[SchemaValidationError])
    end
    def validate_properties(properties); end
  end
end
