# typed: true
# frozen_string_literal: true

module RepositoryRulesets
  class CustomPropertyDescriptor < PropertyDescriptor

    sig do
      params(
        definition: ::CustomProperties::IPropertyDefinition,
      ).void
    end
    def initialize(definition)
      super(
        property_name: definition.property_name,
        description: definition.description,
        value_type: definition.value_type,
        allowed_values: definition.allowed_values,
        source: "custom",
        icon: "note",
        display_name: "Property: #{definition.property_name}"
      )
    end
  end
end
