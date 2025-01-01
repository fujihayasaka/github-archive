# typed: strict
# frozen_string_literal: true

module CustomProperties
  module IValuesManager
    extend T::Helpers

    include Kernel
    include CustomProperties::Errors

    interface!

    sig do
      abstract.params(
        targets: T::Array[T.untyped],
        properties: T::Hash[String, PropertyValue],
        actor: T.nilable(AuthzdActor),
        # Temp flag to move permissions check to the repos domain. FF: `custom_properties_domain_isolation`
        check_permissions: T::Boolean,
      ).void
    end
    def set_properties_for(targets, properties, actor: nil, check_permissions: true); end

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
