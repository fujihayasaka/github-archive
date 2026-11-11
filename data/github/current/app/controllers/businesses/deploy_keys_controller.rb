# typed: true
# frozen_string_literal: true

class Businesses::DeployKeysController < Businesses::MemberPrivilegesController
  def update
    message = nil
    case update_deploy_key_policy_params[:deploy_key_policy]
    when "no_policy"
      this_business.clear_deploy_key_policy(actor: current_user)
      message = "Deploy key policy removed."
    when "enabled"
      this_business.enable_deploy_key_policy(actor: current_user)
      message = "Deploy key policy enabled."
    when "disabled"
      this_business.disable_deploy_key_policy(actor: current_user)
      message = "Deploy key policy disabled."
    end

    redirect_to settings_member_privileges_enterprise_path(this_business), notice: message
  end

  private

  memoize def update_deploy_key_policy_params
    params.require(:business).permit(:deploy_key_policy, :no_policy, :enabled, :disabled)
  end
end
