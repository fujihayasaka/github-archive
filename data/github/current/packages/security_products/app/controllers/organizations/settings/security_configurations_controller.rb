# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityConfigurationsController < Orgs::Controller
  extend T::Sig
  include ReactHelper
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include EnablementSettingsDependency

  PERMITTED_PARAMS = %i(name description) + SecurityConfiguration::ALL_FEATURES
  # We also need to permit the parameters for any feature options that we accept as part of a configuration, so
  # we iterate over any defined feature columns and collect the parameters from the corresponding sub-class of
  # ServiceProduct::Service::Options.
  PERMITTED_OPTIONS_PARAMS = SecurityConfiguration::FEATURE_OPTIONS.each_with_object({}) do |(opts_attr, opts_class), permit|
    permit[opts_attr] = opts_class.as_params
  end

  sig { returns(String) }
  def self.react_bundle_name
    "security-products-enablement"
  end

  allow_verified_fetch only: [:create, :update, :destroy, :repositories_count]

  # Access
  before_action :manage_security_products_permission_required

  before_action :parse_json_params, only: [:create, :update]
  before_action :prevent_duplicate_enablement_events, only: [:update, :destroy]
  before_action :find_security_configuration, only: [:edit, :update, :destroy, :repositories_count]

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
    add_client_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS,
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
      security_configuration_params.merge({ "target" => current_organization }),
      params[:default_for_new_public_repos],
      params[:default_for_new_private_repos],
      params[:enforcement]&.to_sym
    )

    if saved_config.errors.any?
      render json: { errors: saved_config.errors.to_hash }, status: :unprocessable_entity
    else
      render json: {}, status: :created
    end
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def edit
    add_client_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS,
      entity: current_organization)

    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          @security_configuration,
          details: true
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
    add_client_feature_flag(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS,
      entity: current_organization)

    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          SecurityConfiguration.github_recommended_configuration,
          details: true
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
    @security_configuration.update_configuration(
      security_configuration_params.merge({ "target" => current_organization }),
      current_user,
      default_for_new_public_repos: params[:default_for_new_public_repos],
      default_for_new_private_repos: params[:default_for_new_private_repos],
      enforcement: params[:enforcement]&.to_sym
    )

    if @security_configuration.errors.any?
      render json: { errors: @security_configuration.errors.to_hash }, status: :unprocessable_entity
    else
      render json: {}, status: :ok
    end

  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotUnique => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  sig { void }
  def destroy
    @security_configuration.destroy
    head :no_content
  end

  def repositories_count # rubocop:todo GitHub/UseRestfulActions
    render json: {
      repo_count: @security_configuration.repositories_count
    }
  end

  private

  sig { returns(SecurityProductsEnablement::SecurityProductsManager) }
  memoize def manager
    SecurityProductsEnablement::SecurityProductsManager.new
  end

  sig { returns(T.nilable(SecurityConfiguration)) }
  memoize def find_security_configuration
    if SecurityConfiguration.github_recommended_configuration && params.dig(:security_configuration, :name) == SecurityConfiguration::GH_CONFIG_NAME
      @security_configuration = SecurityConfiguration.github_recommended_configuration

      # Confirm that the config provided by the request is indeed GH recommended, and not a custom config that has the same name
      return @security_configuration if params[:id].present? && @security_configuration&.id == params[:id].to_i

      # If the config provided by the request is not GH recommended, reset the variable
      @security_configuration = nil
    end

    @security_configuration = SecurityConfiguration.where(target: current_organization).find(params[:id])
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def security_configuration_params
    result = params.require(:security_configuration).permit(PERMITTED_PARAMS, PERMITTED_OPTIONS_PARAMS).to_h
    result = filter_security_scanning_validity_checks(result)
    result
  end

  sig { params(config_params: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
  def filter_security_scanning_validity_checks(config_params)
    return config_params if T.must(current_organization).feature_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS)

    if config_params["secret_scanning"] == "disabled" || !manager.secret_scanning_enabled? || GitHub.enterprise?
      config_params["secret_scanning_validity_checks"] = "disabled"
    else
      config_params["secret_scanning_validity_checks"] = "not_set"
    end
    config_params
  end
end
