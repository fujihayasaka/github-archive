# typed: true
# frozen_string_literal: true

class Stafftools::BusinessLimitsController < StafftoolsController
  depends_on_clusters \
    ApplicationRecord::Authnd,
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    if request_for_business?
      render "stafftools/business_limits/show",
        layout: "layouts/stafftools/business",
        locals: { limits_target: limits_target }
    else
      render "stafftools/business_limits/show",
        layout: "stafftools",
        locals: { limits_target: limits_target }
    end
  end

  def update
    limits_target.set_organizations_per_business_soft_and_hard_limits!(
      soft_limit: params[:organizations_per_business_soft_limit],
      hard_limit: params[:organizations_per_business_limit],
      actor: current_user
    )
    limits_target.set_members_per_business_soft_and_hard_limits!(
      soft_limit: params[:members_per_business_soft_limit],
      hard_limit: params[:members_per_business_limit],
      actor: current_user
    )
    flash[:notice] = successful_update_message
  rescue Limits::Validator::LimitValueError => error
    flash[:error] = error.message
  ensure
    redirect_to redirect_url
  end

  def destroy
    return render_404 unless request_for_business?

    this_business.clear_organizations_per_business_limit(actor: current_user)
    this_business.clear_organizations_per_business_soft_limit(actor: current_user)
    this_business.clear_members_per_business_limit(actor: current_user)
    this_business.clear_members_per_business_soft_limit(actor: current_user)

    flash[:notice] = "Enterprise limits reset to global limits for the #{this_business} enterprise."
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

  def successful_update_message
    if request_for_business?
      "Enterprise limits updated for the #{this_business} enterprise."
    else
      "Global enterprise limits updated."
    end
  end

  def redirect_url
    if request_for_business?
      stafftools_enterprise_enterprise_limits_path(this_business)
    else
      stafftools_enterprise_limits_path
    end
  end
end
