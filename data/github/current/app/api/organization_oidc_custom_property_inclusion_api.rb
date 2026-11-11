# typed: true
# frozen_string_literal: true

class Api::OrganizationOIDCCustomPropertyInclusionApi < Api::App
  include Api::App::OIDCRepoPropertyInclusionHelper

  get "/organizations/:organization_id/actions/oidc/customization/properties/repo", operation_id: "oidc/list-oidc-custom-property-inclusions-for-org" do
    org = find_org!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:actions_oidc_custom_repo_properties, org, org.business, default: false)
    control_access :read_org_oidc_custom_property_inclusion,
      forbid: true,
      allow_integrations: true,
      resource: org,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    inclusions = list_effective_repo_property_inclusions_for_source(org)
    deliver :oidc_custom_property_inclusion_hash, inclusions
  rescue ActiveRecord::ActiveRecordError => e
    deliver_error! 400, message: e.message
  end

  post "/organizations/:organization_id/actions/oidc/customization/properties/repo", operation_id: "oidc/create-oidc-custom-property-inclusion-for-org", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:actions_oidc_custom_repo_properties, org, org.business, default: false)
    control_access :write_org_oidc_custom_property_inclusion,
      forbid: true,
      allow_integrations: true,
      resource: org,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    data = receive_with_openapi
    custom_property_name = data["custom_property_name"]

    with_write(clusters: [ApplicationRecord::ActionsEnvironments]) do
      begin
        inclusion = create_repo_property_inclusion_for_organization!(org, custom_property_name)
        deliver :oidc_custom_property_inclusion_hash, inclusion, status: 201
      rescue Api::App::OIDCRepoPropertyInclusionHelper::PropertyNotFoundError => e
        deliver_error! 404, message: e.message
      rescue Api::App::OIDCRepoPropertyInclusionHelper::LimitExceededError => e
        deliver_error! 422, message: e.message
      rescue ActiveRecord::RecordInvalid => e
        deliver_error! 422, message: e.message
      rescue ActiveRecord::ActiveRecordError => e
        deliver_error! 400, message: e.message
      end
    end
  end

  delete "/organizations/:organization_id/actions/oidc/customization/properties/repo/:custom_property_name", operation_id: "oidc/delete-oidc-custom-property-inclusion-for-org", read_from_replicas: true do
    org = find_org!
    deliver_error! 404 unless FeatureFlag.vexi.enabled?(:actions_oidc_custom_repo_properties, org, org.business, default: false)
    control_access :write_org_oidc_custom_property_inclusion,
      forbid: true,
      allow_integrations: true,
      resource: org,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: true

    custom_property_name = params[:custom_property_name]

    with_write(clusters: [ApplicationRecord::ActionsEnvironments]) do
      begin
        deleted_count = delete_repo_property_inclusion_for_organization(org, custom_property_name)

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
