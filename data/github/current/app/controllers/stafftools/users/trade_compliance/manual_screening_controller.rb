# typed: strict
# frozen_string_literal: true

class Stafftools::Users::TradeCompliance::ManualScreeningController < Stafftools::Users::TradeComplianceController

  sig { void }
  def create
    if this_user.has_saved_trade_screening_record?
      this_user.perform_live_sdn_screening(force: true)
      flash[:notice] = "Successfully screened for #{this_user}"
    else
      flash[:error] = "Manual screening cannot be performed. #{this_user} doesn't have a valid trade screening record"
    end
    redirect_back(fallback_location: stafftools_user_administrative_tasks_path(this_user))
  end
end
