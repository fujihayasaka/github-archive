# typed: true
# frozen_string_literal: true

class Api::OrganizationCustomPropertiesSchema < Api::App
  include CustomProperties::Errors
  include ReceiveSchemaWithOpenApi

  # Schema of the properties for a organization
  get "/organizations/:organization_id/properties/schema", operation_id: "orgs/get-all-custom-properties" do
    org = find_org!
    manager = definitions_manager(org)

    control_access :read_org_custom_properties,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver :property_definition_hash, manager.get_definitions
  end

  get "/organizations/:organization_id/properties/schema/:custom_property_name", operation_id: "orgs/get-custom-property" do
    org = find_org!

    control_access :read_org_custom_properties,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    definition = find_definition(org)

    deliver :property_definition_hash, definition
  end

  patch "/organizations/:organization_id/properties/schema", operation_id: "orgs/create-or-update-custom-properties" do
    org = find_org!
    manager = definitions_manager(org)

    control_access :manage_org_custom_properties_definitions,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    begin
      Repository.transaction do
        data["properties"].each do |definition|
          manager.save_definition(**definition.symbolize_keys)
        end
      end

      deliver :property_definition_hash, manager.get_definitions
    rescue DefinitionLimitReachedError, InvalidDefinition, DefinitionDeletionError, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  put "/organizations/:organization_id/properties/schema/:custom_property_name", operation_id: "orgs/create-or-update-custom-property" do
    org = find_org!

    control_access :manage_org_custom_properties_definitions,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      manager = definitions_manager(org)
      data = receive_with_openapi

      definition = manager.save_definition(**data.symbolize_keys, property_name: params[:custom_property_name])

      deliver :property_definition_hash, definition
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  delete "/organizations/:organization_id/properties/schema/:custom_property_name", operation_id: "orgs/remove-custom-property" do
    org = find_org!

    control_access :manage_org_custom_properties_definitions,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    manager = definitions_manager(org)

    begin
      delete_definition = manager.delete_definition(params[:custom_property_name])
      deliver_error! 404 unless delete_definition

      deliver_empty status: 204
    rescue DefinitionDeletionError => exception
      deliver_error! 422, message: exception.message
    end
  end

  def definitions_manager(org)
    ::CustomProperties::Public.definitions_manager(org)
  end

  def find_definition(org)
    manager = definitions_manager(org)
    manager.get_definition(params[:custom_property_name])
  end
end
