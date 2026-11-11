# typed: true
# frozen_string_literal: true

class Stafftools::EnterpriseTeamLimitsController < StafftoolsController
  depends_on_clusters \
    ApplicationRecord::Authnd,
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  before_action :ensure_visible

  def show
    if request_for_business?
      render "stafftools/enterprise_team_limits/show",
        layout: "layouts/stafftools/business",
        locals: { limits_target: limits_target }
    else
      render "stafftools/enterprise_team_limits/show",
        layout: "stafftools",
        locals: { limits_target: limits_target }
    end
  end

  def update
    limits_target.set_business_teams_per_business_soft_and_hard_limits!(
      soft_limit: params[:teams_per_business_soft_limit],
      hard_limit: params[:teams_per_business_limit],
      actor: current_user
    )
    limits_target.set_business_team_member_soft_and_hard_limits!(
      soft_limit: params[:member_soft_limit],
      hard_limit: params[:member_limit],
      actor: current_user
    )
    limits_target.set_business_team_organization_assignment_soft_and_hard_limits!(
      soft_limit: params[:organization_assignment_soft_limit],
      hard_limit: params[:organization_assignment_limit],
      actor: current_user
    )

    unless request_for_business?
      GitHub.set_business_team_clear_team_indirect_org_access_job_limit(
        Limits::Validator.validate_limit_value!(params[:clear_team_indirect_org_access_job_limit]),
        actor: current_user
      )
      GitHub.set_business_team_org_remove_member_job_limit(
        Limits::Validator.validate_limit_value!(params[:org_remove_member_job_limit]),
        actor: current_user
      )
      GitHub.set_business_orchestration_remove_org_user_email_settings_job_limit(
        Limits::Validator.validate_limit_value!(params[:orchestration_remove_org_user_email_settings_job_limit]),
        actor: current_user
      )
      GitHub.set_business_orchestration_notify_repository_access_changed_job_limit(
        Limits::Validator.validate_limit_value!(params[:orchestration_notify_repository_access_changed_job_limit]),
        actor: current_user
      )
      GitHub.set_business_orchestration_instrument_removal_job_limit(
        Limits::Validator.validate_limit_value!(params[:orchestration_instrument_removal_job_limit]),
        actor: current_user
      )
    end
    flash[:notice] = successful_update_message
  rescue Limits::Validator::LimitValueError => error
    flash[:error] = error.message
  ensure
    redirect_to redirect_url
  end

  def destroy
    unless request_for_business?
      flash[:error] = "Reset is only available for individual enterprises."
      redirect_to stafftools_enterprise_team_limits_path
      return
    end

    this_business.clear_business_team_member_limit(actor: current_user)
    this_business.clear_business_team_member_soft_limit(actor: current_user)
    this_business.clear_business_team_organization_assignment_limit(actor: current_user)
    this_business.clear_business_team_organization_assignment_soft_limit(actor: current_user)
    this_business.clear_business_teams_per_business_limit(actor: current_user)
    this_business.clear_business_teams_per_business_soft_limit(actor: current_user)

    flash[:notice] = "Enterprise team limits reset to global defaults for the #{this_business} enterprise."
    redirect_to stafftools_enterprise_enterprise_team_limits_path(this_business)
  end

  private

  def ensure_visible
    # Hide in GHES
    render_404 unless GitHub.can_change_enterprise_team_limits?

    # Hide if request_for_business? and in GHES. Only global limits can be changed in GHES.
    render_404 if request_for_business? && GitHub.single_business_environment?

    # Hide if BusinessTeam disabled for the business
    render_404 if request_for_business? && !BusinessTeam.enabled_for_enterprise?(business: this_business) && !this_business.enterprise_teams_enabled?
  end

  def request_for_business?
    this_business.present?
  end

  memoize def this_business
    return unless params[:slug].present?
    Business.find_by(slug: params[:slug])
  end
  helper_method :this_business

  def limits_target
    if this_business.present?
      this_business
    else
      GitHub
    end
  end

  def successful_update_message
    if request_for_business?
      "Enterprise team limits updated for the #{this_business} enterprise."
    else
      "Global enterprise team limits updated."
    end
  end

  def redirect_url
    if request_for_business?
      stafftools_enterprise_enterprise_team_limits_path(this_business)
    else
      stafftools_enterprise_team_limits_path
    end
  end
end
