# typed: true
# frozen_string_literal: true

class Orgs::Settings::DependencyInsightsController < Orgs::Controller
  before_action :login_required
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    return render_404 unless current_organization.dependency_insights_enabled_for?(current_user)

    if %w[0 1].include?(params[:members_can_view_dependency_insights])
      notice = if params[:members_can_view_dependency_insights] == "1"
        current_organization.allow_members_can_view_dependency_insights(actor: current_user)
        "Members can now view dependency insights."
      else
        current_organization.disallow_members_can_view_dependency_insights(actor: current_user)
        "Members can no longer view dependency insights."
      end

      redirect_to :back, notice: notice
    else
      flash[:error] = "You specified an invalid value for the 'members can view dependency insights' setting."
      redirect_to :back
    end
  end
end
