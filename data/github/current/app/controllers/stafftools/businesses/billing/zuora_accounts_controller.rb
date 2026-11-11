# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::ZuoraAccountsController < Stafftools::Businesses::BillingController
  def destroy
    customer = this_business.customer
    if customer.update(zuora_account_id: nil, zuora_account_number: nil)
      flash[:notice] = "Zuora account unlinked from #{this_business.name}."
    else
      flash[:error] = "Failed to unlink Zuora account from #{this_business.name}."
    end
    redirect_to stafftools_enterprise_billing_path(this_business)
  end
end
