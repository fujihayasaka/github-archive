# typed: true
# frozen_string_literal: true

class Api::Organizations::CustomProperties::OrganizationValues < Api::App
  include CustomPropertiesCore::Errors
  include ReceiveSchemaWithOpenApi

  get "/organizations/:organization_id/org-properties/values", operation_id: "orgs/custom-properties-for-orgs-get-organization-values" do
    organization = find_org!
    ensure_org_belongs_to_business!(organization)

    control_access :standard_authorization,
      resource: organization,
      permission: :read_custom_properties_for_organizations,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless Orgs.domain.custom_properties.feature_enabled?(organization)

    property_values = T.must(Orgs.domain.custom_properties.values_for_targets([organization], value_to_use: :effective, strip_nils: true)[organization])
    deliver :custom_properties_value_hash, property_values
  end

  patch "/organizations/:organization_id/org-properties/values", operation_id: "orgs/custom-properties-for-orgs-create-or-update-organization-values", read_from_replicas: true do
    organization = find_org!
    ensure_org_belongs_to_business!(organization)

    control_access :standard_authorization,
      resource: organization,
      permission: :edit_custom_properties_for_organizations,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless Orgs.domain.custom_properties.feature_enabled?(organization)

    data = receive_with_openapi

    data_properties = data["properties"]
    property_names = data_properties.map { |property| property["property_name"] }

    duplicate_properties = property_names.tally.select { |_, count| count > 1 }.keys
    deliver_error! 422, message: "Updated properties must be unique, found duplicates: #{duplicate_properties.join(', ')}" if duplicate_properties.any?

    properties = data_properties.to_h { |property| [property["property_name"], property["value"]] }

    begin
      with_write(clusters: [ApplicationRecord::Repositories]) do
        Orgs.domain.custom_properties.set_properties_for(organization.business, [organization], properties, actor: current_user)
      end
      deliver_empty status: 204
    rescue PropertyValidationError, EditPropertyPermissionError, ArgumentError => exception
      deliver_error! 422, message: exception.message
    end
  end

  def ensure_org_belongs_to_business!(org)
    deliver_error! 404 unless org.business
  end
end
