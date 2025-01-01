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
    contact = Billing::Contact.find_by(id: params[:contact_id])
    if contact.nil? || !contact.persisted?
      flash[:warning] = "No contact was found"
      redirect_to :back
      return
    end
    contact.update_zuora_account_information(customer:)
    if this_business.trade_screening_record.vat_code.present?
      this_business.trade_screening_record.sync_vat_code
    end
    flash[:notice] = "Contact information synchronization enqueued."
    redirect_to :back
  end
end
