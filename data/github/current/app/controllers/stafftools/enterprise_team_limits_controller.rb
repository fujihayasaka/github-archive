# typed: true
# frozen_string_literal: true

class Stafftools::EnterpriseTeamLimitsController < StafftoolsController
  depends_on_clusters \
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
    # Validate first
    if params[:member_limit]
      member_limit_value = integer_from_param(params[:member_limit])
    end

    if params[:organization_assignment_limit]
      organization_assignment_limit_value = integer_from_param(params[:organization_assignment_limit])
    end

    if params[:teams_per_business_limit]
      teams_per_business_limit_value = integer_from_param(params[:teams_per_business_limit])
    end

    # Then update
    if params[:member_limit]
      limits_target.set_business_team_member_limit(member_limit_value, actor: current_user)
    end

    if params[:organization_assignment_limit]
      limits_target.set_business_team_organization_assignment_limit(organization_assignment_limit_value, actor: current_user)
    end

    if params[:teams_per_business_limit]
      limits_target.set_business_teams_per_business_limit(teams_per_business_limit_value, actor: current_user)
    end

    flash[:notice] = successful_update_message
  rescue TypeError, ArgumentError
    flash[:error] = "All limits must be zero or greater."
  ensure
    redirect_to redirect_url
  end

  private

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

  def integer_from_param(param)
    result = Integer(param)
    raise ArgumentError if result < 0
    result
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
