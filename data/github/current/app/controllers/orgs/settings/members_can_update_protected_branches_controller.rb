# typed: true
# frozen_string_literal: true

class Orgs::Settings::MembersCanUpdateProtectedBranchesController < Orgs::Controller
  before_action :login_required
  before_action :org_admins_only
  before_action :update_protected_branches_setting_flag_required, only: :update
  after_action :customer_category_instrumentation

  def update
    case params[:members_can_update_protected_branches]
    when "1"
      current_organization.allow_members_can_update_protected_branches(actor: current_user)
      redirect_to :back, notice: "Members can now update protected branches."
    when "0"
      current_organization.disallow_members_can_update_protected_branches(actor: current_user)
      redirect_to :back, notice: "Members can no longer update protected branches."
    else
      flash[:error] = "You specified an invalid value for the 'members can update protected branches' setting."
      redirect_to :back
    end
  end

  private

  def update_protected_branches_setting_flag_required
    render_404 unless GitHub.update_protected_branches_setting_enabled? || FeatureFlag.vexi.enabled?(:update_protected_branches_setting, current_organization, default: false)
  end
end
