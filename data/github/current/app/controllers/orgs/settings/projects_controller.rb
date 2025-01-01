# typed: true
# frozen_string_literal: true

class Orgs::Settings::ProjectsController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  stylesheet_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    view = create_view_model(
      ::Settings::Organization::ProjectsView,
      organization: current_organization
    )
    render "settings/organization/projects", locals: { view: view }
  end

  def update
    args = params.require(:organization).permit(
      :organization_projects_enabled,
      :projects_increased_limits_public_beta_enabled,
      :members_can_change_project_visibility
    )

    if args[:organization_projects_enabled] == "1"
      current_organization.enable_organization_projects(actor: current_user)
    else
      current_organization.disable_organization_projects(actor: current_user)
    end

    if args[:members_can_change_project_visibility] == "1"
      current_organization.allow_members_to_change_project_visibility(actor: current_user)
    else
      current_organization.block_members_from_changing_project_visibility(actor: current_user)
    end

    if current_organization.feature_enabled?(:memex_project_without_limits_public_beta_safe_rollout) ||
      current_organization.feature_enabled?(:memex_project_without_limits_public_beta)

      if args[:projects_increased_limits_public_beta_enabled] == "1"
        current_organization.enable_feature(:memex_project_without_limits_public_beta)
      else
        current_organization.disable_feature(:memex_project_without_limits_public_beta)
      end
    end

    flash[:notice] = "Projects settings updated for this organization."

    redirect_to :back
  end
end
