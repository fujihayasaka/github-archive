# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityConfigurationsController < Orgs::Controller
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

  # other actions might need this_organization too (feel free to add to this list if you find them),
  # but this is the only one explicitly referencing it here
  before_action :this_organization_required, only: [:new]

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
    add_client_feature_flag(SecurityConfigurations::FeatureFlagHelper.client_feature_flags, entity: current_organization)

    render_react_app(
      payload: default_payload,
      title: "Settings · New configuration · #{current_organization.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "organization_settings",
    )
  end

  sig { void }
  def create
    klass = current_organization.advanced_security_products_bundled? ? SecurityConfiguration : UnbundledSecurityConfiguration
    saved_config = klass.create_configuration(
      model_hash: security_configuration_params(current_organization).merge({ "target" => current_organization }),
      default_for_new_public_repos: params[:default_for_new_public_repos],
      default_for_new_private_repos: params[:default_for_new_private_repos],
      enforcement: SecurityConfigurationPolicy::Enforcement.from_string(params[:enforcement]),
      actor: current_user,
      options: params[:options]
    )

    if saved_config.errors.any?
      errors = serialize_errors(saved_config.errors)
      GitHub.logger.info log_with_context("gh.security_configuration.errors": errors)
      render json: { errors: }, status: :unprocessable_entity
    else
      render json: {}, status: :created
    end
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotUnique => e
    GitHub.logger.info log_with_context("gh.security_configuration.errors": e.message)
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def edit
    add_client_feature_flag(SecurityConfigurations::FeatureFlagHelper.client_feature_flags, entity: current_organization)

    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          security_configuration,
          details: true,
          actor: current_user,
        ),
      }),
      title: "Settings · Edit configuration · #{current_organization.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "organization_settings",
    )
  end

  def show
    add_client_feature_flag(SecurityConfigurations::FeatureFlagHelper.client_feature_flags, entity: current_organization)

    render_react_app(
      payload: default_payload.merge({
        securityConfiguration: security_configuration_serializer.serialize(
          security_configuration,
          details: true,
          actor: current_user,
        ),
      }),
      title: "Settings · Show configuration · #{current_organization.name}",
      page_data: {
        selected_link: :security_products,
      },
      layout: "organization_settings",
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
        enforcement: SecurityConfigurationPolicy::Enforcement.from_string(params[:enforcement]),
        options: params[:options],
      )
    else
      security_configuration.update_configuration(
        security_configuration_params(current_organization).merge({ "target" => current_organization }),
        T.must(current_user),
        type: :organization,
        default_for_new_public_repos: params[:default_for_new_public_repos],
        default_for_new_private_repos: params[:default_for_new_private_repos],
        enforcement: SecurityConfigurationPolicy::Enforcement.from_string(params[:enforcement]),
        options: params[:options],
      )
    end

    if security_configuration.errors.any?
      errors = serialize_errors(security_configuration.errors)
      GitHub.logger.info log_with_context(
        "gh.security_configuration.errors": errors,
        "gh.security_configuration.id": security_configuration.id,
      )
      render json: { errors: }, status: :unprocessable_entity
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

  private

  sig { params(logs: Hash).returns(Hash) }
  def log_with_context(logs)
    logs.merge({
      action: action_name,
      controller: self.class.name,
      "gh.actor.id": current_user&.id,
      "gh.actor.login": current_user&.display_login,
      "gh.org.login": current_organization&.display_login,
    })
  end
end
