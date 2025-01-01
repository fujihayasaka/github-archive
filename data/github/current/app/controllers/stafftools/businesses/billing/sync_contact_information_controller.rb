# typed: strict
# frozen_string_literal: true

class Stafftools::Businesses::Billing::SyncContactInformationController < Stafftools::Businesses::BusinessBaseController
  sig { void }
  def update
    customer = this_business.customer
    if customer.nil?
      flash[:warning] = "No customer exists for this account"
      redirect_to :back
      return
    end
    contact = customer.billing_contact
    if contact.nil?
      flash[:warning] = "No contact was found"
      redirect_to :back
      return
    end
    customer.update_contact_information
    if customer.vat_code.present?
      customer.sync_vat_code
    end
    flash[:notice] = "Contact information synchronization enqueued."
    redirect_to :back
  end
end
