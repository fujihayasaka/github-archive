# typed: strict
# frozen_string_literal: true

module Orgs::CustomPropertiesHelper
  include AvatarHelper

  MAX_DISPLAYED_ORG_CONFLICT_USAGES = 10
  MAX_DISPLAYED_ALLOWED_VALUES = 30

  # Produces definitions payload.
  # If skip_allowed_values_above_threshold is true, allowed values are only included
  # when their count is less than or equal to MAX_DISPLAYED_ALLOWED_VALUES.
  sig { params(definitions: T::Array[CustomPropertiesCore::IPropertyDefinition], skip_allowed_values_above_threshold: T::Boolean).returns(T::Array[DefinitionPayload]) }
  def definitions_payload(definitions, skip_allowed_values_above_threshold: false)
    GitHub::PrefillAssociations.prefill_batch_method(definitions, :source)
    definitions.map { |definition| definition_payload(definition, skip_allowed_values_above_threshold:) }
  end

  # Produces definition payload.
  # If skip_allowed_values_above_threshold is true, allowed values are only included
  # when their count is less than or equal to MAX_DISPLAYED_ALLOWED_VALUES.
  sig { params(definition: CustomPropertiesCore::IPropertyDefinition, skip_allowed_values_above_threshold: T::Boolean).returns(DefinitionPayload) }
  def definition_payload(definition, skip_allowed_values_above_threshold: false)
    source = definition.source
    allowed_values = definition.allowed_values

    if skip_allowed_values_above_threshold && allowed_values.present? && allowed_values.size > MAX_DISPLAYED_ALLOWED_VALUES
      allowed_values = nil
    end
    payload = {
      propertyName: definition.property_name,
      valueType: definition.value_type,
      required: definition.required,
      defaultValue: definition.default_value,
      description: definition.description,
      allowedValues: allowed_values,
      valuesEditableBy: definition.values_editable_by,
      regex: definition.regex,
      source: {
        type: definition.source_type,
        name: source.safe_profile_name,
        slug: source.is_a?(Orgs::IOrganization) ? source.display_login : source.slug,
        avatarUrl: avatar_url_for(source)
      }
    }

    # require_explicit_values is exclusive to repo custom properties and we don't want to return this property
    # for other types
    if definition.is_a?(CustomPropertyDefinition)
      payload[:requireExplicitValues] = definition.require_explicit_values
    end

    payload
  end

  # Produces property definitions payload grouped by namespace.
  sig { params(definitions_by_namespace: T::Hash[String, T::Array[CustomPropertiesCore::IPropertyDefinition]]).returns(T::Array[PropertyNamespacePayload]) }
  def namespaced_definitions_payload(definitions_by_namespace)
    definitions_by_namespace.values.flatten.group_by(&:class).each_value do |definitions|
      GitHub::PrefillAssociations.prefill_batch_method(definitions, :source)
    end

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
        definitions: definitions.map { |definition| definition_payload(definition) }
      }
    end
  end

  sig { params(repos: T::Array[::Repository]).returns(T::Array[RepoItemPayload]) }
  def repos_properties_payload(repos)
    repo_properties = Repositories.domain.custom_properties.repo_properties(repos, :manual, strip_nils: true)

    repos.map do |repo|
      {
        id: repo.id,
        name: repo.name,
        description: repo.description,
        visibility: repo.visibility,
        properties: T.must(repo_properties[repo])
      }
    end
  end

  sig do
    params(
      property_name: String,
      all_existing_properties_in_orgs: T::Array[CustomPropertiesCore::IPropertyDefinition],
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

  sig { params(limits: CustomPropertiesCore::PropertyLimits).returns(PropertiesLimitsPayload) }
  def properties_limits_payload(limits)
    {
      maxPropertyValueLength: limits.max_property_value_length,
      maxUrlPropertyValueLength: limits.max_url_property_value_length,
    }
  end

  PropertiesLimitsPayload = T.type_alias do
    {
      maxPropertyValueLength: Integer,
      maxUrlPropertyValueLength: Integer,
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

  PropertyNamespacePayload = T.type_alias do
    {
      namespace: String,
      type: String,
      definitions: T::Array[DefinitionPayload]
    }
  end

  DefinitionPayload = T.type_alias { T.any(RepoPropertyDefinitionPayload, DefinitionPayloadBase) }

  DefinitionPayloadBase = T.type_alias do
    {
      propertyName: String,
      valueType: String,
      required: T::Boolean,
      defaultValue: T.nilable(CustomPropertiesCore::PropertyValue),
      description: T.nilable(String),
      allowedValues: T.nilable(T::Array[String]),
      valuesEditableBy: String,
      regex: T.nilable(String),
      source: {
        type: String,
        name: String,
        slug: String,
        avatarUrl: String,
      }
    }
  end

  RepoPropertyDefinitionPayload = T.type_alias do
    {
      propertyName: String,
      valueType: String,
      required: T::Boolean,
      defaultValue: T.nilable(CustomPropertiesCore::PropertyValue),
      description: T.nilable(String),
      allowedValues: T.nilable(T::Array[String]),
      valuesEditableBy: String,
      regex: T.nilable(String),
      source: {
        type: String,
        name: String,
        slug: String,
        avatarUrl: String,
      },
      requireExplicitValues: T::Boolean,
    }
  end

  RepoItemPayload = T.type_alias do
    {
      id: Integer,
      visibility: String,
      name: String,
      description: T.nilable(String),
      properties: T::Hash[String, T.nilable(CustomPropertiesCore::PropertyValue)]
    }
  end
end
