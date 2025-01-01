# typed: true
# frozen_string_literal: true

class Businesses::MembersCanChangeRepoVisibilityController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  def update
    setting_value = params[:members_can_change_repo_visibility]&.to_s
    validate_setting value: setting_value

    message = ""
    case setting_value
    when "enabled"
      this_business.allow_members_to_change_repo_visibility(actor: current_user, force: true)
      message = "Members can change repository visibilities and this is enforced for this enterprise."
    when "disabled"
      this_business.block_members_from_changing_repo_visibility(actor: current_user, force: true)
      message = "Members cannot change repository visibilities and this is enforced for this enterprise."
    when "no_policy"
      this_business.clear_members_can_change_repo_visibility_setting(actor: current_user)
      message = "Policy removed for repository visibility change setting."
    end

    redirect_to settings_member_privileges_enterprise_path(this_business), notice: message
  end
end
