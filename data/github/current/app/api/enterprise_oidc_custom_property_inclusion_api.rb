# typed: true
# frozen_string_literal: true

class Api::EnterpriseOIDCCustomPropertyInclusionApi < Api::Enterprise::App
  include Api::App::OIDCRepoPropertyInclusionHelper

  get "/enterprises/:enterprise_id/actions/oidc/customization/properties/repo", operation_id: "oidc/list-oidc-custom-property-inclusions-for-enterprise" do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless current_enterprise.feature_flag_enabled?(:actions_oidc_custom_repo_properties, default: false)
    control_access :read_enterprise_oidc_custom_property_inclusion,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: "Must have admin rights to Enterprise."

    inclusions = list_repo_property_inclusions_for_enterprise(current_enterprise)
    deliver :oidc_custom_property_inclusion_hash, inclusions
  rescue ActiveRecord::ActiveRecordError => e
    deliver_error! 400, message: e.message
  end

  post "/enterprises/:enterprise_id/actions/oidc/customization/properties/repo", operation_id: "oidc/create-oidc-custom-property-inclusion-for-enterprise", read_from_replicas: true do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless current_enterprise.feature_flag_enabled?(:actions_oidc_custom_repo_properties, default: false)
    control_access :write_enterprise_oidc_custom_property_inclusion,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: "Must have admin rights to Enterprise."

    data = receive_with_openapi
    custom_property_name = data["custom_property_name"]

    with_write(clusters: [ApplicationRecord::ActionsEnvironments, ApplicationRecord::Repositories]) do
      begin
        inclusion = create_repo_property_inclusion_for_enterprise!(current_enterprise, custom_property_name)
        deliver :oidc_custom_property_inclusion_hash, inclusion, status: 201
      rescue OIDC::RepoCustomPropertyInclusionHelper::PropertyNotFoundError => e
        deliver_error! 404, message: e.message
      rescue OIDC::RepoCustomPropertyInclusionHelper::LimitExceededError => e
        deliver_error! 422, message: e.message
      rescue ActiveRecord::RecordInvalid => e
        deliver_error! 422, message: e.message
      rescue ActiveRecord::ActiveRecordError => e
        deliver_error! 400, message: e.message
      end
    end
  end

  delete "/enterprises/:enterprise_id/actions/oidc/customization/properties/repo/:custom_property_name", operation_id: "oidc/delete-oidc-custom-property-inclusion-for-enterprise", read_from_replicas: true do
    current_enterprise = find_enterprise!
    deliver_error! 404 unless current_enterprise.feature_flag_enabled?(:actions_oidc_custom_repo_properties, default: false)
    control_access :write_enterprise_oidc_custom_property_inclusion,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: "Must have admin rights to Enterprise."

    custom_property_name = params[:custom_property_name]

    with_write(clusters: [ApplicationRecord::ActionsEnvironments, ApplicationRecord::Repositories]) do
      begin
        deleted_count = delete_repo_property_inclusion_for_enterprise(current_enterprise, custom_property_name)

        if deleted_count == 0
          deliver_error! 404, message: "Property '#{custom_property_name}' not found"
        else
          deliver_empty status: 204
        end
      rescue ActiveRecord::ActiveRecordError => e
        deliver_error! 400, message: e.message
      end
    end
  end
end
