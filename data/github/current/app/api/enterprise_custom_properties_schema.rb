# typed: true
# frozen_string_literal: true

class Api::EnterpriseCustomPropertiesSchema < Api::Enterprise::App
  include CustomProperties::Errors
  include ReceiveSchemaWithOpenApi

  get "/enterprises/:enterprise_id/properties/schema", operation_id: "enterprise-admin/get-enterprise-custom-properties" do
    business = find_enterprise!
    return deliver_error 404 unless CustomProperties::Public.enterprise_properties_enabled?(business)

    control_access :read_enterprise_custom_properties,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    manager = definitions_manager(business)
    deliver :property_definition_hash, manager.get_definitions
  end

  patch "/enterprises/:enterprise_id/properties/schema", operation_id: "enterprise-admin/create-or-update-enterprise-custom-properties" do
    business = find_enterprise!
    return deliver_error 404 unless CustomProperties::Public.enterprise_properties_enabled?(business)

    control_access :manage_enterprise_custom_properties_definitions,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      data = receive_with_openapi
      manager = definitions_manager(business)

      Repository.transaction do
        data["properties"].each do |definition|
          manager.save_definition(**definition.symbolize_keys)
        end
      end
      deliver :property_definition_hash, manager.get_definitions
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  get "/enterprises/:enterprise_id/properties/schema/:custom_property_name", operation_id: "enterprise-admin/get-enterprise-custom-property" do
    business = find_enterprise!
    return deliver_error 404 unless CustomProperties::Public.enterprise_properties_enabled?(business)

    control_access :read_enterprise_custom_properties,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    definition = find_definition(business)
    return deliver_error 404 unless definition.present?

    deliver :property_definition_hash, definition
  end

  put "/enterprises/:enterprise_id/properties/schema/:custom_property_name", operation_id: "enterprise-admin/create-or-update-enterprise-custom-property" do
    business = find_enterprise!
    return deliver_error 404 unless CustomProperties::Public.enterprise_properties_enabled?(business)

    control_access :manage_enterprise_custom_properties_definitions,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      data = receive_with_openapi
      manager = definitions_manager(business)

      definition = manager.save_definition(**data.symbolize_keys, property_name: params[:custom_property_name])
      deliver :property_definition_hash, definition
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  put "/enterprises/:enterprise_id/properties/schema/organizations/:org/:custom_property_name/promote", operation_id: "enterprise-admin/promote-custom-property-to-enterprise" do
    business = find_enterprise!
    org = Organization.find_by_login(params[:org])

    return deliver_error 404 unless org.present?
    return deliver_error 404 unless org.business == business
    return deliver_error 404 unless CustomProperties::Public.enterprise_properties_enabled?(business)
    return deliver_error 404 unless business.feature_enabled?(:enterprise_custom_properties_promotion)

    control_access :manage_enterprise_custom_properties_definitions,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: false

    begin
      org_definition = CustomProperties::Public.definitions_manager(org).get_definition(params[:custom_property_name])

      return deliver_error 404 if org_definition.nil?

      definition = definitions_manager(business).promote_definition(org_definition)

      deliver :property_definition_hash, definition
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError => exception
      deliver_error! 422, message: exception.message
    end
  end

  delete "/enterprises/:enterprise_id/properties/schema/:custom_property_name", operation_id: "enterprise-admin/remove-enterprise-custom-property" do
    business = find_enterprise!
    return deliver_error 404 unless CustomProperties::Public.enterprise_properties_enabled?(business)

    control_access :manage_enterprise_custom_properties_definitions,
      resource: business,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      manager = definitions_manager(business)
      delete_definition = manager.delete_definition(params[:custom_property_name])
      deliver_error! 404 unless delete_definition

      deliver_empty status: 204
    rescue InvalidDefinition => exception
      deliver_error! 422, message: exception.message
    end
  end

  private

  sig { params(business: Business).returns(CustomPropertiesBusinessDefinitionsManager) }
  def definitions_manager(business)
    ::CustomProperties::Public.business_definitions_manager(business)
  end

  def find_definition(business)
    manager = definitions_manager(business)
    manager.get_definition(params[:custom_property_name])
  end
end
