# typed: true
# frozen_string_literal: true

class Businesses::PrivateRepositoryForkingController < Businesses::BusinessController
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :business_full_plan_required

  def update
    setting_value = params[:allow_private_repository_forking]&.to_s
    policy_value = params[:allow_private_repository_forking_policy]&.to_s

    # if forced, the org cannot override the value. we should only force if the business hasn't opted in to org policies.
    should_force = false
    validate_setting value: setting_value

    message = ""
    case setting_value
    when "enabled"
      result = this_business.allow_private_repository_forking(force: should_force, actor: current_user, policy: policy_value)
      if !result
        flash[:error] = "Could not set the private repository forking policy for #{this_business} at this time. Please ensure the policy is valid."
      else
        message = "Repository forking policy updated."
      end
    when "disabled"
      this_business.block_private_repository_forking(actor: current_user)
      message = "Private and internal repository forks are disabled and enforced for this enterprise."
    when "no_policy"
      this_business.clear_private_repository_forking_setting(actor: current_user)
      message = "Private and internal repository forks policy removed."
    end

    redirect_to settings_member_privileges_enterprise_path(this_business), notice: message
  end
end
