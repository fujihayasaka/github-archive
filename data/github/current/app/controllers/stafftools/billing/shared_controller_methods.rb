# typed: strict
# frozen_string_literal: true

module Stafftools::Billing::SharedControllerMethods
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { StafftoolsController }

  sig { overridable.returns(Billing::Types::Account) }
  def target
    this_user
  end

  sig { void }
  def update_vat_codes_for_account
    vat_codes_updated = []
    invoice_vat_id, receipt_vat_id = params[:invoice_vat_id], params[:receipt_vat_id]
    if invoice_vat_id.present?
      trade_screening_record = target.trade_screening_record
      unless trade_screening_record.persisted?
        flash[:error] = "Couldn't update invoice VAT id because user has no billing information on file"
        return redirect_to :back
      end
      trade_screening_record.update!(vat_code: invoice_vat_id)
      vat_codes_updated << "invoices"
    end
    if receipt_vat_id.present?
      customer = target.customer
      unless customer.present?
        flash[:error] = "Couldn't update receipt VAT id because user has no customer on file"
        return redirect_to :back
      end
      customer.update!(vat_code: receipt_vat_id)
      vat_codes_updated << "receipts"
    end
    if vat_codes_updated.empty?
      flash[:warning] = "No VAT ID was provided to update"
    else
      flash[:notice] = "VAT ID for #{vat_codes_updated.join(" and ")} updated successfully"
    end
    redirect_to :back
  end
end
