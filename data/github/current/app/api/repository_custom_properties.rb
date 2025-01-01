# typed: true
# frozen_string_literal: true

class Api::RepositoryCustomProperties < Api::App
  include CustomProperties::Errors
  include ReceiveSchemaWithOpenApi

  get "/repositories/:repository_id/properties/values", operation_id: "repos/get-custom-properties-values" do
    ensure_repo_properties! current_repo

    control_access :read_repository_custom_properties,
      resource: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Do not include nil effective values. We do not want the repo level read custom property values to be a way to
    # see all available custom properties defined on an organization. So we only include effective values that are
    # set on the repo.
    property_values = T.must(Repositories.domain.custom_properties.repo_properties([current_repo], :effective, strip_nils: true)[current_repo])
    deliver :repository_properties_effective_value_hash, property_values
  end

  patch "/repositories/:repository_id/properties/values", operation_id: "repos/create-or-update-custom-properties-values" do
    ensure_repo_properties! current_repo

    control_access :edit_repo_custom_properties_values,
      resource: current_repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    data_properties = data["properties"]
    property_names = data_properties.map { |property| property["property_name"] }

    duplicate_properties = property_names.tally.select { |_prop, count| count > 1 }.keys
    deliver_error! 422, message: "Updated properties must be unique, found duplicates: #{duplicate_properties.join(', ')}" if duplicate_properties.any?

    properties = data_properties.to_h { |property| [property["property_name"], property["value"]] }

    begin
      Repositories.domain.custom_properties.set_properties_for(current_repo.owner, [current_repo], properties, actor: current_actor)
      deliver_empty status: 204
    rescue PropertyValidationError, EditPropertyPermissionError, ArgumentError => exception
      deliver_error! 422, message: exception.message
    end
  end

  def ensure_repo_properties!(repo)
    deliver_error! 404 unless current_repo.owner.organization?
  end
end
