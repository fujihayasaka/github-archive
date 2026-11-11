# typed: true
# frozen_string_literal: true

class Businesses::MemberRepositoryDeletionController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  def update
    setting_value = members_can_delete_repos_params[:members_can_delete_repositories]
    validate_setting value: setting_value

    message = ""
    case setting_value
    when "enabled"
      this_business.allow_members_can_delete_repositories(actor: current_user, force: true)
      message = "Members can now delete or transfer repositories."
    when "disabled"
      this_business.disallow_members_can_delete_repositories(actor: current_user, force: true)
      message = "Members can no longer delete or transfer repositories."
    when "no_policy"
      this_business.clear_members_can_delete_repositories(actor: current_user)
      message = "Organization administrators can now change this setting for individual organizations."
    end

    redirect_to :back, notice: message
  end

  private

  memoize def members_can_delete_repos_params
    params.require(:business).permit(:members_can_delete_repositories)
  end
end
