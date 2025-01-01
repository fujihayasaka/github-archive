# typed: true
# frozen_string_literal: true

class Api::Organizations::CustomProperties::EnterpriseSchema < Api::Enterprise::App
  include CustomPropertiesCore::Errors
  include ReceiveSchemaWithOpenApi

  get "/enterprises/:enterprise_id/org-properties/schema", operation_id: "enterprise-admin/custom-properties-for-orgs-get-enterprise-definitions" do
    business = find_enterprise!

    deliver_error! 404 unless Orgs.domain.custom_properties.feature_enabled?(business)

    control_access :standard_authorization,
      resource: business,
      permission: :read_enterprise_custom_properties_for_organizations,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver :org_property_definition_hash, Orgs.domain.custom_properties.get_definitions(business)
  end

  patch "/enterprises/:enterprise_id/org-properties/schema", operation_id: "enterprise-admin/custom-properties-for-orgs-create-or-update-enterprise-definitions", read_from_replicas: true do
    business = find_enterprise!

    deliver_error! 404 unless Orgs.domain.custom_properties.feature_enabled?(business)

    control_access :standard_authorization,
      resource: business,
      permission: :manage_enterprise_custom_properties_for_organizations,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    begin
      data = receive_with_openapi

      with_write(clusters: [ApplicationRecord::Repositories]) do
        Repository.transaction do
          data["properties"].each do |definition|
            Orgs.domain.custom_properties.save_definition(business, **definition.symbolize_keys)
          end
        end
      end

      deliver :org_property_definition_hash, Orgs.domain.custom_properties.get_definitions(business)
    rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
      deliver_error! 422, message: exception.message
    end
  end

  get "/enterprises/:enterprise_id/org-properties/schema/:custom_property_name", operation_id: "enterprise-admin/custom-properties-for-orgs-get-enterprise-definition" do
    business = find_enterprise!

    deliver_error! 404 unless Orgs.domain.custom_properties.feature_enabled?(business)

    control_access :standard_authorization,
      resource: business,
      permission: :read_enterprise_custom_properties_for_organizations,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    definition = Orgs.domain.custom_properties.get_definition(business, params[:custom_property_name])
    deliver_error! 404 unless definition

    deliver :org_property_definition_hash, definition
  end

  put "/enterprises/:enterprise_id/org-properties/schema/:custom_property_name", operation_id: "enterprise-admin/custom-properties-for-orgs-create-or-update-enterprise-definition", read_from_replicas: true do
    business = find_enterprise!

    deliver_error! 404 unless Orgs.domain.custom_properties.feature_enabled?(business)

    control_access :standard_authorization,
      resource: business,
      permission: :manage_enterprise_custom_properties_for_organizations,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    with_write(clusters: [ApplicationRecord::Repositories]) do
      begin
        data = receive_with_openapi
        definition = Orgs.domain.custom_properties.save_definition(business, **data.symbolize_keys, property_name: params[:custom_property_name])

        deliver :org_property_definition_hash, definition
      rescue DefinitionLimitReachedError, InvalidDefinition, ArgumentError, DefinitionDeletionAllowValueInUseError => exception
        deliver_error! 422, message: exception.message
      end
    end
  end

  delete "/enterprises/:enterprise_id/org-properties/schema/:custom_property_name", operation_id: "enterprise-admin/custom-properties-for-orgs-delete-enterprise-definition", read_from_replicas: true do
    business = find_enterprise!

    deliver_error! 404 unless Orgs.domain.custom_properties.feature_enabled?(business)

    control_access :standard_authorization,
      resource: business,
      permission: :manage_enterprise_custom_properties_for_organizations,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    with_write(clusters: [ApplicationRecord::Repositories]) do
      begin
        delete_definition = Orgs.domain.custom_properties.delete_definition(business, params[:custom_property_name])
        deliver_error! 404 unless delete_definition

        deliver_empty status: 204
      rescue InvalidDefinition => exception
        deliver_error! 422, message: exception.message
      end
    end
  end
end
