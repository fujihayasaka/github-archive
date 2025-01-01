# typed: true
# frozen_string_literal: true

class Api::EnterpriseCustomPropertiesSchema < Api::Enterprise::App
  include CustomProperties::Errors
  include ReceiveSchemaWithOpenApi

  get "/enterprises/:enterprise_id/properties/schema", operation_id: "enterprise-admin/get-enterprise-custom-properties" do
    business = find_enterprise!
    return deliver_error 404 unless business.feature_enabled?(:enterprise_custom_properties)

    manager = definitions_manager(business)

    control_access :read_enterprise_custom_properties,
      resource: business,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    deliver :property_definition_hash, manager.get_definitions
  end

  def definitions_manager(business)
    ::CustomProperties::Public.definitions_manager(business)
  end
end
