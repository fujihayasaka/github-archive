# typed: strict
# frozen_string_literal: true

module Orgs::CustomPropertiesHelper
  include AvatarHelper

  MAX_DISPLAYED_ORG_CONFLICT_USAGES = 10

  sig { params(definitions: T::Array[CustomProperties::IPropertyDefinition]).returns(T::Array[DefinitionPayload]) }
  def definitions_payload(definitions)
    GitHub::PrefillAssociations.prefill_batch_method(definitions, :source)
    definitions.map { |definition| definition_payload(definition) }
  end

  sig { params(definition: CustomProperties::IPropertyDefinition).returns(DefinitionPayload) }
  def definition_payload(definition)
    source = definition.source
    {
      propertyName: definition.property_name,
      valueType: definition.value_type,
      required: definition.required,
      defaultValue: definition.default_value,
      description: definition.description,
      allowedValues: definition.allowed_values,
      valuesEditableBy: definition.values_editable_by,
      regex: definition.regex,
      sourceType: definition.source_type,
      source: {
        type: definition.source_type,
        name: source.safe_profile_name,
        slug: source.is_a?(Orgs::IOrganization) ? source.display_login : source.slug,
        avatarUrl: avatar_url_for(source)
      }
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

  sig do
    params(
      property_name: String,
      all_existing_properties_in_orgs: T::Array[CustomProperties::IPropertyDefinition],
      max_displayed_usages: Integer
    ).returns(OrgConflictsPayload)
  end
  def org_conflicts_payload(property_name, all_existing_properties_in_orgs, max_displayed_usages: MAX_DISPLAYED_ORG_CONFLICT_USAGES)
    truncated_orgs_using_property = all_existing_properties_in_orgs.take(max_displayed_usages).index_by(&:source_id)
    orgs_with_property_name = Organization.where(id: truncated_orgs_using_property.keys)

    orgs_with_property_name_payload = orgs_with_property_name.map do |org|
      property = truncated_orgs_using_property[org.id]
      {
        name: org.display_login,
        avatarUrl: avatar_url_for(org),
        propertyType: property.value_type
      }
    end

    {
      usages: orgs_with_property_name_payload,
      totalUsageCount: all_existing_properties_in_orgs.count
    }
  end

  OrgConflictsPayload = T.type_alias do
    {
      usages: T::Array[OrgDefinitionPayload],
      totalUsageCount: Integer
    }
  end

  OrgDefinitionPayload = T.type_alias do
    {
      name: String,
      avatarUrl: String,
      propertyType: String
    }
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
      sourceType: String,
      source: {
        type: String,
        name: String,
        slug: String,
        avatarUrl: String,
      }
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
