# app/controllers/stafftools/businesses/billing/reset_attempts_controller.rb
# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::ResetAttemptsController < Stafftools::Businesses::BillingController
  def update
    this_business.reset_billing_attempts

    audit_log_payload = {
      business: this_business,
      customer_id: this_business.customer_id.to_s,
    }

    if this_business.billing_attempts == 0
      GitHub.instrument "billing.reset_billing_attempts", audit_log_payload.merge({ status: "success" })
      flash[:notice] = "Billing attempts reset"
    else
      GitHub.instrument "billing.reset_billing_attempts", audit_log_payload.merge({ status: "failure" })
      flash[:error] = "Billing attempts could not be reset"
    end


    redirect_to stafftools_enterprise_billing_path(this_business)
  end
end
