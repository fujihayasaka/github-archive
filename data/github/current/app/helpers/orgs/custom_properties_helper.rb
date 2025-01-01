# typed: strict
# frozen_string_literal: true

module Orgs::CustomPropertiesHelper
  extend T::Sig

  sig { params(definitions: T::Array[CustomProperties::IPropertyDefinition]).returns(T::Array[DefinitionPayload]) }
  def definitions_payload(definitions)
    definitions.map { |definition| definition_payload(definition) }
  end

  sig { params(definitions: T::Array[CustomProperties::IPropertyDefinition]).returns(T::Array[DefinitionPayloadWithSourceType]) }
  def definitions_payload_with_source_type(definitions)
    definitions.map { |definition| definition_payload_with_source_type(definition) }
  end


  # ANY UPDATES HERE SHOULD BE REFLECTED IN definition_payload_with_source_type
  sig { params(definition: CustomProperties::IPropertyDefinition).returns(DefinitionPayload) }
  def definition_payload(definition)
    {
      propertyName: definition.property_name,
      valueType: definition.value_type,
      required: definition.required,
      defaultValue: definition.default_value,
      description: definition.description,
      allowedValues: definition.allowed_values,
      valuesEditableBy: definition.values_editable_by,
      regex: definition.regex,
    }
  end

  # TODO: consolidate with definition_payload
  # ANY UPDATES HERE SHOULD BE REFLECTED IN definition_payload
  sig { params(definition: CustomProperties::IPropertyDefinition).returns(DefinitionPayloadWithSourceType) }
  def definition_payload_with_source_type(definition)
    {
      propertyName: definition.property_name,
      valueType: definition.value_type,
      required: definition.required,
      defaultValue: definition.default_value,
      description: definition.description,
      allowedValues: definition.allowed_values,
      valuesEditableBy: definition.values_editable_by,
      regex: definition.regex,
      sourceType: definition.source_type
    }
  end

  sig { params(usages: T::Array[CustomProperties::IPropertyUsage]).returns(T::Array[T::Hash[String, String]]) }
  def property_usages_payload(usages)
    usages.map { |usage| property_usage_payload(usage) }
  end

  sig { params(usage: CustomProperties::IPropertyUsage).returns(T::Hash[String, String]) }
  def property_usage_payload(usage)
    { value: usage.property_value, consumerType: usage.consumer_type }
  end

  sig { params(repos: T::Array[::Repository]).returns(T::Array[RepoItemPayload]) }
  def repos_properties_payload(repos)
    repo_properties = CustomProperties::Public.repo_properties(repos, :manual, strip_nils: true)

    repos.map do |repo|
      {
        id: T.must(repo.id),
        name: T.must(repo.name),
        description: repo.description,
        visibility: repo.visibility,
        properties: T.must(repo_properties[repo])
      }
    end
  end

  DefinitionPayload = T.type_alias do
    {
      propertyName: String,
      valueType: String,
      required: T::Boolean,
      defaultValue: T.nilable(CustomProperties::PropertyValue),
      description: T.nilable(String),
      allowedValues: T.nilable(T::Array[String]),
      valuesEditableBy: String,
      regex: T.nilable(String),
    }
  end

  DefinitionPayloadWithSourceType = T.type_alias do
    {
      propertyName: String,
      valueType: String,
      required: T::Boolean,
      defaultValue: T.nilable(CustomProperties::PropertyValue),
      description: T.nilable(String),
      allowedValues: T.nilable(T::Array[String]),
      valuesEditableBy: String,
      regex: T.nilable(String),
      sourceType: String,
    }
  end

  RepoItemPayload = T.type_alias do
    {
      id: Integer,
      visibility: String,
      name: String,
      description: T.nilable(String),
      properties: T::Hash[String, T.nilable(CustomProperties::PropertyValue)]
    }
  end
end
