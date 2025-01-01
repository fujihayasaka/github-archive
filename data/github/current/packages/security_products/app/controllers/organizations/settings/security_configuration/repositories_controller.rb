# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityConfiguration::RepositoriesController < Orgs::Controller
  extend T::Sig

  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include EnablementSettingsDependency
  include Settings::SecurityProducts::RepositoriesHelper

  allow_verified_fetch only: [:update, :destroy]

  # Access
  before_action :manage_security_products_permission_required
  before_action :prevent_duplicate_enablement_events, only: [:update, :destroy]
  before_action :parse_json_params, only: [:update, :destroy]
  before_action :find_security_configuration, only: [:update]

  sig { void }
  def update
    is_gh_config = @security_configuration.is_github_recommended_configuration?
    options = if is_gh_config
      {
        default_for_new_public_repos: params[:default_for_new_public_repos],
        default_for_new_private_repos: params[:default_for_new_private_repos],
      }
    else
      {}
    end

    SecurityProductsEnablement::OrganizationSecurityConfigurationJob.perform_later(
      security_configuration_id: @security_configuration.id,
      organization_id: current_organization.id,
      actor_id: current_user.id,
      action: :apply,
      repository_ids: params[:repository_ids],
      repository_query: params[:repository_query],
      override_existing_config: params[:override_existing_config] == true,
      user_session_id: user_session.id,
      options:
    )

    if %w(config_table repos_table).include?(params[:source])
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

  private

  sig { void }
  def find_security_configuration
    @security_configuration = SecurityConfiguration.where(target: current_organization).find_by(id: params[:id])
    return if @security_configuration.present?

    @security_configuration = SecurityConfiguration.github_recommended_configuration

    render_404 unless @security_configuration.present? && @security_configuration.id == params[:id].to_i
  end
end
