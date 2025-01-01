# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::TradeCompliance::ManualScreeningController < Stafftools::Businesses::TradeComplianceController

  sig { void }
  def create
    if this_business.has_saved_trade_screening_record?
      this_business.perform_live_sdn_screening(force: true)
      flash[:notice] = "Successfully screened for #{this_business}"
    else
      flash[:error] = "Manual screening cannot be performed. #{this_business} doesn't have a valid trade screening record"
    end

    redirect_back(fallback_location: stafftools_enterprise_trade_compliance_path(this_business))
  end
end
