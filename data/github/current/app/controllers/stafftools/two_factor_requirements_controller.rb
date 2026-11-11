# typed: true
# frozen_string_literal: true

class Stafftools::TwoFactorRequirementsController < StafftoolsController
  before_action :ensure_user_exists

  def exempt_2fa_requirement # rubocop:todo GitHub/UseRestfulActions
    reason = params[:"exempt-reason"]

    if this_user.two_factor_requirement_metadata.nil?
      flash[:error] = "User does not have a 2FA requirement"
    elsif reason.blank?
      flash[:error] = "You must provide a reason for the log"
    else
      this_user.two_factor_requirement_metadata.update!(state: User::AccountTwoFactorRequirementDependency::TWO_FACTOR_REQUIREMENT_STATES[:exempt])
      instrument("staff.two_factor_requirement.exempt", user: this_user, note: reason)
      GitHub.dogstats.increment("two_factor_requirement.users.exempted")
      flash[:notice] = "2FA requirement exempted for @#{this_user}"
    end

    redirect_to :back
  end
end
