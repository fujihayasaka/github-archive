# typed: true
# frozen_string_literal: true

class Api::Repositories::CustomProperties::EnterpriseSchema < Api::Enterprise::App
  include CustomPropertiesCore::Errors
  include ReceiveSchemaWithOpenApi

  get "/enterprises/:enterprise_id/properties/schema", operation_id: "enterprise-admin/custom-properties-for-repos-get-enterprise-definitions" do
    business = find_enterprise!

    control_access :read_enterprise_custom_properties,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver :property_definition_hash, Repositories.domain.custom_properties.get_definitions(business)
  end

  patch "/enterprises/:enterprise_id/properties/schema", operation_id: "enterprise-admin/custom-properties-for-repos-create-or-update-enterprise-definitions" do
    business = find_enterprise!

    control_access :manage_enterprise_custom_properties_definitions,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      data = receive_with_openapi

      Repository.transaction do
        data["properties"].each do |definition|
          Repositories.domain.custom_properties.save_definition(business, **definition.symbolize_keys)
        end
      end

      deliver :property_definition_hash, Repositories.domain.custom_properties.get_definitions(business)
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  get "/enterprises/:enterprise_id/properties/schema/:custom_property_name", operation_id: "enterprise-admin/custom-properties-for-repos-get-enterprise-definition" do
    business = find_enterprise!

    control_access :read_enterprise_custom_properties,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    definition = Repositories.domain.custom_properties.get_definition(business, params[:custom_property_name])
    return deliver_error 404 if definition.nil?

    deliver :property_definition_hash, definition
  end

  put "/enterprises/:enterprise_id/properties/schema/:custom_property_name", operation_id: "enterprise-admin/custom-properties-for-repos-create-or-update-enterprise-definition" do
    business = find_enterprise!

    control_access :manage_enterprise_custom_properties_definitions,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      data = receive_with_openapi
      definition = Repositories.domain.custom_properties.save_definition(business, **data.symbolize_keys, property_name: params[:custom_property_name])
      deliver :property_definition_hash, definition
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  put "/enterprises/:enterprise_id/properties/schema/organizations/:org/:custom_property_name/promote", operation_id: "enterprise-admin/custom-properties-for-repos-promote-definition-to-enterprise" do
    business = find_enterprise!
    org = Organization.find_by_login(params[:org])

    return deliver_error 404 unless org.present?
    return deliver_error 404 unless org.business == business

    control_access :manage_enterprise_custom_properties_definitions,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: false

    begin
      org_definition = Repositories.domain.custom_properties.get_definition(org, params[:custom_property_name])

      return deliver_error 404 if org_definition.nil?

      definition = Repositories.domain.custom_properties.promote_definition(business, org_definition)

      deliver :property_definition_hash, definition
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError => exception
      deliver_error! 422, message: exception.message
    end
  end

  delete "/enterprises/:enterprise_id/properties/schema/:custom_property_name", operation_id: "enterprise-admin/custom-properties-for-repos-delete-enterprise-definition" do
    business = find_enterprise!

    control_access :manage_enterprise_custom_properties_definitions,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      delete_definition = Repositories.domain.custom_properties.delete_definition(business, params[:custom_property_name])
      deliver_error! 404 unless delete_definition
      deliver_empty status: 204
    rescue InvalidDefinition => exception
      deliver_error! 422, message: exception.message
    end
  end
end
