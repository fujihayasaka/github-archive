# typed: true
# frozen_string_literal: true

class Orgs::Settings::MemberIssueDeletionController < Orgs::Controller
  before_action :login_required
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    if %w[0 1].include?(params[:members_can_delete_issues])
      notice = if params[:members_can_delete_issues] == "1"
        current_organization.allow_members_can_delete_issues(actor: current_user)
        "Members can now delete issues."
      else
        current_organization.disallow_members_can_delete_issues(actor: current_user)
        "Members can no longer delete issues."
      end

      redirect_to :back, notice: notice
    else
      flash[:error] = "You specified an invalid value for the 'members can delete issues' setting."
      redirect_to :back
    end
  end
end
