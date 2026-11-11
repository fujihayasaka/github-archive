# typed: strict
# frozen_string_literal: true

class Api::Repositories::ExternalProperties::OrganizationValues < Api::App
  include CustomPropertiesCore::Errors
  include ReceiveSchemaWithOpenApi

  # Update provided external property values for specified repos in an organization
  patch "/organizations/:organization_id/properties/external/values", operation_id: "orgs/external-properties-for-repos-create-or-update-organization-values", read_from_replicas: true do
    org = find_org!

    deliver_error! 404 unless Repositories.domain.custom_properties.external_properties_enabled?(org)

    control_access :edit_org_external_properties_values,
      resource: org,
      allow_integrations: true,
      allow_user_via_granular_actor: false

    data = receive_with_openapi

    data_properties = data["properties"]
    property_names = data_properties.map { |property| property["property_name"] }

    duplicate_properties = property_names.tally.select { |_prop, count| count > 1 }.keys
    deliver_error! 422, message: "Updated properties must be unique, found duplicates: #{duplicate_properties.join(', ')}" if duplicate_properties.any?

    names = Array(data["repository_names"])
    repos = org.repositories.active.where(name: names).to_a

    missing_names = names - repos.map(&:name)
    deliver_error! 422, message: "Repository name not found: #{missing_names.join(', ')}" if missing_names.any?

    properties = data_properties.to_h { |property| [property["property_name"], property["value"]] }

    begin
      # control_access checks confirm that the caller current_integration_installation is a non-nil integration installed on the given org
      ActiveRecord::Base.connected_to(role: :writing) do
        Repositories.domain.custom_properties.set_external_properties_for(current_integration_installation, repos, properties)
      end
      deliver_empty status: 204
    rescue PropertyValidationError, DefinitionLimitReachedError, ArgumentError => exception
      deliver_error! 422, message: exception.message
    end
  end
end
