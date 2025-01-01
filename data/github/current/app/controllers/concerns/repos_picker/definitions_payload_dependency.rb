# typed: strict
# frozen_string_literal: true

module ReposPicker::DefinitionsPayloadDependency
  FilterPropertyDefinition = T.type_alias do
    {
      propertyName: String,
      valueType: String,
      allowedValues: T.nilable(T::Array[String]),
    }
  end

  sig { params(definitions: T::Array[CustomProperties::IPropertyDefinition]).returns(T::Array[FilterPropertyDefinition]) }
  def definitions_payload(definitions)
    definitions.map { |definition| definition_payload(definition) }
  end

  sig { params(definition: CustomProperties::IPropertyDefinition).returns(FilterPropertyDefinition) }
  def definition_payload(definition)
    {
      propertyName: definition.property_name,
      valueType: definition.value_type,
      allowedValues: definition.allowed_values,
    }
  end
end
