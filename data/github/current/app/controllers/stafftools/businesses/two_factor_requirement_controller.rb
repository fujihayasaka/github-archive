# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::TwoFactorRequirementController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required

  def destroy
    this_business.disable_two_factor_required(actor: current_user, log_event: true)
    flash[:notice] = "Disabled two-factor authentication requirement policy.
      Individual organizations may enable or disable two-factor authentication.".squish
    redirect_to :back
  end
end
