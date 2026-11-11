# typed: true
# frozen_string_literal: true

class Stafftools::OrganizationLimitsController < StafftoolsController
  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    if request_for_organization?
      render "stafftools/organization_limits/show",
        layout: "layouts/stafftools/organization/overview",
        locals: { limits_target: limits_target }
    else
      render "stafftools/organization_limits/show",
        layout: "stafftools",
        locals: { limits_target: limits_target }
    end
  end

  def update
    # Validate first
    if params[:teams_per_organization_limit]
      teams_limit_value = integer_from_param(params[:teams_per_organization_limit])
    end

    if params[:teams_per_organization_soft_limit]
      teams_soft_limit_value = integer_from_param(params[:teams_per_organization_soft_limit])
    end

    if params[:members_per_organization_limit]
      members_limit_value = integer_from_param(params[:members_per_organization_limit])
    end

    if params[:members_per_organization_soft_limit]
      members_soft_limit_value = integer_from_param(params[:members_per_organization_soft_limit])
    end

    # Then update
    if params[:teams_per_organization_limit]
      limits_target.set_teams_per_organization_limit(teams_limit_value, actor: current_user)
    end

    if params[:teams_per_organization_soft_limit]
      limits_target.set_teams_per_organization_soft_limit(teams_soft_limit_value, actor: current_user)
    end

    if params[:members_per_organization_limit]
      limits_target.set_members_per_organization_limit(members_limit_value, actor: current_user)
    end

    if params[:members_per_organization_soft_limit]
      limits_target.set_members_per_organization_soft_limit(members_soft_limit_value, actor: current_user)
    end

    flash[:notice] = successful_update_message
  rescue TypeError, ArgumentError
    flash[:error] = "All limits must be zero or greater."
  ensure
    redirect_to redirect_url
  end

  def destroy
    return render_404 unless request_for_organization?

    this_organization.clear_teams_per_organization_limit(actor: current_user)
    this_organization.clear_teams_per_organization_soft_limit(actor: current_user)
    this_organization.clear_members_per_organization_limit(actor: current_user)
    this_organization.clear_members_per_organization_soft_limit(actor: current_user)

    flash[:notice] = "Organization limits reset to global limits for the #{this_organization} organization."
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
      "Organization limits updated for the #{this_organization} organization."
    else
      "Global organization limits updated."
    end
  end

  def redirect_url
    if request_for_organization?
      stafftools_user_organization_limits_path(this_organization)
    else
      stafftools_organization_limits_path
    end
  end
end
