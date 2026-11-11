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

  FilterPropertyNamespace = T.type_alias do
    {
      namespace: String,
      type: String,
      definitions: T::Array[FilterPropertyDefinition]
    }
  end

  sig { params(definitions_by_namespace: T::Hash[String, T::Array[CustomPropertiesCore::IPropertyDefinition]]).returns(T::Array[FilterPropertyNamespace]) }
  def namespaced_definitions_payload(definitions_by_namespace)
    definitions_by_namespace.filter_map do |namespace, definitions|
      types = definitions.map(&:type).uniq
      type = types.first
      if type.nil? || types.size != 1
        GitHub.logger.error(
          "Property definitions under namespace have nil or mixed types",
          "gh.custom_properties.namespace" => namespace,
          "gh.custom_properties.types" => types.join(","),
        )
        next
      end

      {
        namespace: namespace,
        type: type,
        definitions: definitions_payload(definitions)
      }
    end
  end

  sig { params(definitions: T::Array[CustomPropertiesCore::IPropertyDefinition]).returns(T::Array[FilterPropertyDefinition]) }
  def definitions_payload(definitions)
    definitions.map { |definition| definition_payload(definition) }
  end

  sig { params(definition: CustomPropertiesCore::IPropertyDefinition).returns(FilterPropertyDefinition) }
  def definition_payload(definition)
    {
      propertyName: definition.property_name,
      valueType: definition.value_type,
      allowedValues: definition.allowed_values,
    }
  end
end
