# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::BillingTypeController < Stafftools::Businesses::BillingController
  include Stafftools::Businesses::TradeCompliance::SharedControllerMethods

  before_action :ensure_target_not_restricted

  def update
    if this_business.enterprise_managed?
      flash[:error] = "The billing type of an enterprise managed enterprise cannot be changed."
    else
      return render_404 if this_business.trial? || this_business.trial_cancelled?

      if params[:billing_type] == Customer::BILLING_TYPE_INVOICE
        return render_404 if this_business.invoiced?
        this_business.switch_to_invoiced_payments
        flash[:notice] = "Switched the #{this_business.name} enterprise to invoiced payments."
      elsif params[:billing_type] == Customer::BILLING_TYPE_CARD
        return render_404 if this_business.self_serve_payment?
        this_business.enable_self_serve_payments(plan_duration: params[:plan_duration])
        flash[:notice] = "Enabled self-serve payments for the #{this_business.name} enterprise."
      end
    end

    redirect_to stafftools_enterprise_path(this_business)
  end
end
