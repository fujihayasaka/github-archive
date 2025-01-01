# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityConfiguration::RepositoriesController < Orgs::Controller

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include EnablementSettingsDependency
  include SecurityConfigurations::RepositoriesDependency

  allow_verified_fetch only: [:update, :destroy]

  # Access
  before_action :manage_security_products_permission_required
  before_action :prevent_duplicate_enablement_events, only: [:update, :destroy]
  before_action :parse_json_params, only: [:update, :destroy]
  before_action :security_configuration, only: [:update]

  sig { void }
  def update

    # we only want to update the defaults if they are present in the params
    # so that we can treat nil values as "do not change"
    if params.key?("default_for_new_public_repos") && params.key?("default_for_new_private_repos")
      SecurityConfigurationDefault.create_or_update_defaults(
        target: current_organization,
        security_configuration: security_configuration,
        default_for_new_public_repos: params["default_for_new_public_repos"],
        default_for_new_private_repos: params["default_for_new_private_repos"],
      )
    end

    SecurityProductsEnablement::OrganizationSecurityConfigurationJob.perform_later(
      security_configuration_id: security_configuration.id,
      organization_id: current_organization.id,
      actor_id: current_user.id,
      action: :apply,
      repository_ids: params[:repository_ids],
      repository_query: params[:repository_query],
      override_existing_config: params[:override_existing_config] == true,
      user_session_id: user_session.id,
      options: {}
    )

    if %w(config_table repos_table).include?(params[:source])
      is_gh_config = security_configuration.is_github_recommended_configuration?
      analytics_event(
        category: is_gh_config ? "apply_gh_config" : "apply_custom_config",
        action: params[:source],
        label: "org_id:#{current_organization.id}",
      )
    end

    head :created
  end

  sig { void }
  def destroy
    SecurityProductsEnablement::OrganizationSecurityConfigurationJob.perform_later(
      security_configuration_id: nil,
      organization_id: current_organization.id,
      actor_id: current_user.id,
      action: :detach,
      repository_ids: params[:repository_ids],
      repository_query: params[:repository_query],
      user_session_id: user_session.id,
    )

    head :ok
  end
end
