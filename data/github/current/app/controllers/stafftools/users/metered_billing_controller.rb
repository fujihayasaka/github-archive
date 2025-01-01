# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/ControllersShouldHaveTests
class Stafftools::Users::MeteredBillingController < StafftoolsController
  # rubocop:enable GitHub/ControllersShouldHaveTests
  include Stafftools::Users::ControllerLayoutMethods

  layout :billing_layout

  before_action :ensure_user_exists


  def advance_quota_reset_date # rubocop:todo GitHub/UseRestfulActions
    if this_user.advance_metered_cycle_reset_date!
      flash[:notice] = "Successfully moved reset date to #{this_user.reload.next_metered_billing_cycle_starts_at.to_date}"
    else
      flash[:error] = "Failed to advance reset date"
    end

    redirect_to billing_stafftools_user_url(this_user)
  end
end
