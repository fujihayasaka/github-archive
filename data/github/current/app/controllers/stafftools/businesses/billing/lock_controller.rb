# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::LockController < Stafftools::Businesses::BillingController
  include Stafftools::Businesses::TradeCompliance::SharedControllerMethods

  before_action :ensure_target_not_restricted

  def update
    operation = params[:operation]&.to_sym

    case operation
    when :lock
      this_business.disable! if this_business.enabled?
      flash[:notice] = "Enterprise billing locked."
    when :unlock
      this_business.unlock_billing! if this_business.disabled?
      flash[:notice] = "Enterprise billing unlocked."
    else
      flash[:error] = "Invalid enterprise billing lock operation provided."
    end

    redirect_to stafftools_enterprise_billing_path(this_business)
  end
end
