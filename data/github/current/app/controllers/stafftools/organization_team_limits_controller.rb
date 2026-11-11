# typed: true
# frozen_string_literal: true

class Stafftools::OrganizationTeamLimitsController < StafftoolsController
  depends_on_clusters \
    ApplicationRecord::Authnd,
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    if request_for_organization?
      render "stafftools/organization_team_limits/show",
        layout: "layouts/stafftools/organization/overview",
        locals: { limits_target: limits_target }
    else
      render "stafftools/organization_team_limits/show",
        layout: "stafftools",
        locals: { limits_target: limits_target }
    end
  end

  def update
    limits_target.set_members_per_org_team_soft_and_hard_limits!(
      soft_limit: params[:members_per_org_team_soft_limit],
      hard_limit: params[:members_per_org_team_limit],
      actor: current_user
    )
    flash[:notice] = successful_update_message
  rescue Limits::Validator::LimitValueError => error
    flash[:error] = error.message
  ensure
    redirect_to redirect_url
  end

  def destroy
    return render_404 unless request_for_organization?

    this_organization.clear_members_per_org_team_limit(actor: current_user)
    this_organization.clear_members_per_org_team_soft_limit(actor: current_user)

    flash[:notice] = "Organization team limits reset to global limits for the #{this_organization} organization."
    redirect_to redirect_url
  end

  private

  def request_for_organization?
    this_organization.present?
  end

  memoize def this_organization
    return unless params[:user_id].present?
    Organization.find_by(login: params[:user_id])
  end
  helper_method :this_organization

  def limits_target
    if this_organization.present?
      this_organization
    else
      GitHub
    end
  end

  def successful_update_message
    if request_for_organization?
      "Organization team limits updated for the #{this_organization} organization."
    else
      "Global organization team limits updated."
    end
  end

  def redirect_url
    if request_for_organization?
      stafftools_user_organization_team_limits_path(this_organization)
    else
      stafftools_organization_team_limits_path
    end
  end
end
