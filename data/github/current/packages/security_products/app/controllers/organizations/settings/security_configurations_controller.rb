# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityConfigurationsController < Orgs::Controller
  include ReactHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include EnablementSettingsDependency

  sig { returns(String) }
  def self.react_bundle_name
    "security-products-enablement"
  end

  allow_verified_fetch only: [:create, :update, :destroy, :repositories_count]

  # Access
  before_action :manage_security_products_permission_required

  before_action :parse_json_params, only: [:create, :update]
  before_action :prevent_duplicate_enablement_events, only: [:update, :destroy]
  before_action :security_configuration, only: [:edit, :update, :show, :repositories_count]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    ApplicationRecord::SecurityOverviewAnalytics,
    only: [:new, :edit, :show]

  sig { void }
  def new
    add_client_feature_flag([SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS],
      entity: current_organization)

    render_react_app(
      payload: default_payload,
      title: "Settings · New security configuration · #{current_organization.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "organization_settings",
      ssr: true,
    )
  end

  sig { void }
  def create
    saved_config = SecurityConfiguration.create_configuration(
      security_configuration_params(current_organization).merge({ "target" => current_organization }),
      params[:default_for_new_public_repos],
      params[:default_for_new_private_repos],
      params[:enforcement]&.to_sym,
      current_user,
      params[:options],
    )

    if saved_config.errors.any?
      render json: { errors: serialize_errors(saved_config.errors) }, status: :unprocessable_entity
    else
      render json: {}, status: :created
    end
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def edit
    add_client_feature_flag([SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS],
      entity: current_organization)

    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          security_configuration,
          details: true,
          actor: current_user,
        ),
      }),
      title: "Settings · Edit security configuration · #{current_organization.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "organization_settings",
      ssr: true,
    )
  end

  def show
    add_client_feature_flag([SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS],
      entity: current_organization)

    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          security_configuration,
          details: true,
          actor: current_user,
        ),
      }),
      title: "Settings · Show security configuration · #{current_organization.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "organization_settings",
      ssr: true,
    )
  end

  sig { void }
  def update
    if security_configuration.belongs_to_enterprise?
      business = current_organization.business
      security_configuration.update_configuration(
        { "target" => business },
        T.must(current_user),
        type: :enterprise,
        policies_target: current_organization,
        default_for_new_public_repos: params[:default_for_new_public_repos],
        default_for_new_private_repos: params[:default_for_new_private_repos],
        enforcement: params[:enforcement]&.to_sym,
        options: params[:options],
      )
    else
      security_configuration.update_configuration(
        security_configuration_params(current_organization).merge({ "target" => current_organization }),
        T.must(current_user),
        type: :organization,
        default_for_new_public_repos: params[:default_for_new_public_repos],
        default_for_new_private_repos: params[:default_for_new_private_repos],
        enforcement: params[:enforcement]&.to_sym,
        options: params[:options],
      )
    end

    if security_configuration.errors.any?
      render json: { errors: serialize_errors(security_configuration.errors) }, status: :unprocessable_entity
    else
      render json: {}, status: :ok
    end

  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  sig { void }
  def destroy
    security_configuration = SecurityConfiguration.find_by(target: [current_organization], id: params[:id])
    if security_configuration.present?
      security_configuration.delete_configuration(current_user)
      head :no_content
    else
      render_404
    end
  end

  def repositories_count # rubocop:todo GitHub/UseRestfulActions
    render json: {
      repo_count: security_configuration_serializer.repositories_count(security_configuration)
    }
  end
end
