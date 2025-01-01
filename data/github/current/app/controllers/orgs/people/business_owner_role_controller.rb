# typed: true
# frozen_string_literal: true

class Orgs::People::BusinessOwnerRoleController < Orgs::Controller
  before_action :login_required
  before_action :business_owner_required
  before_action :unsuspended_business_required
  before_action :sudo_filter

  def update
    role_change_status = business_owner.change_role(params[:role])

    case role_change_status
    when Organization::BusinessOwnerStatus::SUCCESS_OWNER
      flash[:notice] = "You've become an owner of #{this_organization.safe_profile_name}!"
    when Organization::BusinessOwnerStatus::SUCCESS_MEMBER
      flash[:notice] = "You've become a member of #{this_organization.safe_profile_name}!"
    when Organization::BusinessOwnerStatus::SUCCESS_REMOVED
      flash[:notice] = "You've removed your membership from #{this_organization.safe_profile_name}. It may take a few minutes for the removal to process."
    when Organization::BusinessOwnerStatus::NO_CHANGE
      flash[:notice] = "No change was made to your role for #{this_organization.safe_profile_name}."
    else
      flash[:error] = role_change_status.message
    end

    redirect_to :back
  end

  private

  memoize def business_owner
    Organization::BusinessOwner.new(organization: this_organization, business_owner: current_user)
  end

  def business_owner_required
    render_404 unless this_organization&.business&.owner?(current_user)
  end

  def unsuspended_business_required
    render_404 if this_organization&.business&.suspended? && !current_user.site_admin?
  end
end
