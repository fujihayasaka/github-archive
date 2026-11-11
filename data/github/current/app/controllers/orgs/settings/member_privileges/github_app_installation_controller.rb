# typed: true
# frozen_string_literal: true

class Orgs::Settings::MemberPrivileges::GitHubAppInstallationController < Orgs::Controller
  before_action :organization_admin_required
  before_action :ensure_feature_flag_is_active

  ALLOW_REPO_ADMINS_TO_INSTALL_GITHUB_APPS = {
    off: "0",
    on: "1",
  }.freeze

  def update
    return render_error unless valid_parameter?

    notice = set_allow_github_app_installation_by_repo_admins!

    redirect_to :back, notice: notice
  end

  private

  def valid_parameter?
    ALLOW_REPO_ADMINS_TO_INSTALL_GITHUB_APPS.values.include?(params[:allow_github_app_installation_by_repo_admins])
  end

  def render_error
    flash[:error] = "You specified an invalid value for the 'Repository admin GitHub Apps installation' setting."
    redirect_to :back
  end

  def ensure_feature_flag_is_active
    render_404 unless FeatureFlag.vexi.enabled?(:repo_admin_github_apps_setting, current_organization, default: false)
  end

  def set_allow_github_app_installation_by_repo_admins!
    if params[:allow_github_app_installation_by_repo_admins] == ALLOW_REPO_ADMINS_TO_INSTALL_GITHUB_APPS[:on]
      current_organization.allow_github_app_installation_by_non_org_owner_repo_admins(actor: current_user)
      "Repository admins can now install GitHub Apps."
    else
      current_organization.disallow_github_app_installation_by_non_org_owner_repo_admins(actor: current_user)
      "Repository admins can no longer install GitHub Apps for their repositories."
    end
  end
end
