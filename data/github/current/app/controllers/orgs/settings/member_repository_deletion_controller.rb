# typed: true
# frozen_string_literal: true

class Orgs::Settings::MemberRepositoryDeletionController < Orgs::Controller
  before_action :login_required
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    if %w[0 1].include?(params[:members_can_delete_repositories])
      notice = if params[:members_can_delete_repositories] == "1"
        current_organization.allow_members_can_delete_repositories(actor: current_user)
        "Members can now delete or transfer repositories."
      else
        current_organization.disallow_members_can_delete_repositories(actor: current_user)
        "Members can no longer delete or transfer repositories."
      end

      redirect_to :back, notice: notice
    else
      flash[:error] = "You specified an invalid value for the 'members can delete repositories' setting."
      redirect_to :back
    end
  end
end
