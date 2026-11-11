# typed: true
# frozen_string_literal: true

class Api::Organizations::CustomProperties::EnterpriseValues < Api::Enterprise::App
  include CustomPropertiesCore::Errors
  include ReceiveSchemaWithOpenApi

  get "/enterprises/:enterprise_id/org-properties/values", operation_id: "enterprise-admin/custom-properties-for-orgs-get-enterprise-values" do
    business = find_enterprise!

    deliver_error! 404 unless Orgs.domain.custom_properties.feature_enabled?(business)

    control_access :standard_authorization,
      resource: business,
      permission: :read_enterprise_custom_properties_for_organizations,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    organizations = business.organizations.order(:display_login).paginate(page: pagination[:page], per_page: pagination[:per_page])
    values_by_orgs = Orgs.domain.custom_properties.values_for_targets(organizations, value_to_use: :effective, strip_nils: false)

    data = organizations.map do |org|
      {
        organization: org,
        property_values: values_by_orgs[org]
      }
    end

    # The deliver method will automatically set the pagination headers
    # but it needs to know the collection_size. It can infer it if the object passed to deliver
    # is an active record relation or a hash, but in this case it's an array of hashes so we
    # must manually set the collection size.
    paginator.collection_size = organizations.total_entries

    deliver :org_property_effective_values_hash, data
  end

  patch "/enterprises/:enterprise_id/org-properties/values", operation_id: "enterprise-admin/custom-properties-for-orgs-create-or-update-enterprise-values", read_from_replicas: true do
    business = find_enterprise!

    deliver_error! 404 unless Orgs.domain.custom_properties.feature_enabled?(business)

    control_access :standard_authorization,
      resource: business,
      permission: :edit_enterprise_custom_properties_for_organizations,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    data_properties = data["properties"]
    property_names = data_properties.map { |property| property["property_name"] }

    duplicate_properties = property_names.tally.select { |_prop, count| count > 1 }.keys
    deliver_error! 422, message: "Updated properties must be unique, found duplicates: #{duplicate_properties.join(', ')}" if duplicate_properties.any?

    display_login = Array(data["organization_logins"])
    orgs = business.organizations.where(display_login: display_login).to_a

    missing_logins = display_login - orgs.map(&:display_login)
    deliver_error! 422, message: "Organization login not found: #{missing_logins.sort.join(', ')}" if missing_logins.any?

    properties = data_properties.to_h { |property| [property["property_name"], property["value"]] }

    begin
      with_write(clusters: [ApplicationRecord::Repositories]) do
        Orgs.domain.custom_properties.set_properties_for(business, orgs, properties, actor: current_user)
      end
      deliver_empty status: 204
    rescue PropertyValidationError, ArgumentError => exception
      deliver_error! 422, message: exception.message
    end
  end
end
