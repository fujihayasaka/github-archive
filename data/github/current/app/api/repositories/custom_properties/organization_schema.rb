# typed: true
# frozen_string_literal: true

class Api::Repositories::CustomProperties::OrganizationSchema < Api::App
  include CustomPropertiesCore::Errors
  include ReceiveSchemaWithOpenApi

  # Schema of the properties for a organization
  get "/organizations/:organization_id/properties/schema", operation_id: "orgs/custom-properties-for-repos-get-organization-definitions" do
    org = find_org!

    control_access :read_org_custom_properties,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    definitions = Repositories.domain.custom_properties.get_definitions(org)
    preload_org_source_business(definitions)
    deliver :repo_property_definition_hash, definitions
  end

  get "/organizations/:organization_id/properties/schema/:custom_property_name", operation_id: "orgs/custom-properties-for-repos-get-organization-definition" do
    org = find_org!

    control_access :read_org_custom_properties,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    definition = Repositories.domain.custom_properties.get_definition(org, params[:custom_property_name])
    return deliver_error 404 if definition.nil?

    if definition.source_type != "org"
      deliver_error! 422, message: "Cannot access property '#{definition.property_name}'. Property is defined at enterprise level."
    end

    deliver :repo_property_definition_hash, definition
  end

  patch "/organizations/:organization_id/properties/schema", operation_id: "orgs/custom-properties-for-repos-create-or-update-organization-definitions" do
    org = find_org!

    control_access :manage_org_custom_properties_definitions,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    begin
      duplicates = data["properties"]
        .map { |definition| definition["property_name"].downcase }
        .tally.select { |_, count| count > 1 }
        .keys

      if duplicates.any?
        names = duplicates.map { |name| "'#{name}'" }.join(", ")
        raise ArgumentError.new "Multiple updates for the same #{"property".pluralize(duplicates.size)} are found: #{names}. Property name uniqueness is case insensitive."
      end

      Repository.transaction do
        data["properties"].each do |definition|
          Repositories.domain.custom_properties.save_definition(org, **definition.symbolize_keys)
        end
      end

      definitions = Repositories.domain.custom_properties.get_definitions(org)
      preload_org_source_business(definitions)
      deliver :repo_property_definition_hash, definitions
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  put "/organizations/:organization_id/properties/schema/:custom_property_name", operation_id: "orgs/custom-properties-for-repos-create-or-update-organization-definition" do
    org = find_org!

    control_access :manage_org_custom_properties_definitions,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      data = receive_with_openapi
      definition = Repositories.domain.custom_properties.save_definition(org, **data.symbolize_keys, property_name: params[:custom_property_name])
      deliver :repo_property_definition_hash, definition
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  delete "/organizations/:organization_id/properties/schema/:custom_property_name", operation_id: "orgs/custom-properties-for-repos-delete-organization-definition" do
    org = find_org!

    control_access :manage_org_custom_properties_definitions,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      delete_definition = Repositories.domain.custom_properties.delete_definition(org, params[:custom_property_name])
      deliver_error! 404 if delete_definition.nil?
      deliver_empty status: 204
    rescue InvalidDefinition => exception
      deliver_error! 422, message: exception.message
    end
  end

  private

  def preload_org_source_business(definitions)
    GitHub::PrefillAssociations.prefill_batch_method(definitions, :source)
    org_sources = definitions.filter_map(&:source).grep(Organization).uniq
    GitHub::PrefillAssociations.prefill_associations(org_sources, [:business])
  end
end
