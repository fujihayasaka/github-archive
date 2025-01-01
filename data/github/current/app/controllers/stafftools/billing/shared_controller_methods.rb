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
    errors = []
    vat_id = params[:vat_id]
    delete_vat_id = params[:delete_vat_id] == "1"

    if target.has_update_trade_restrictions?
      flash[:warn] = "The VAT ID cannot be updated due to trade restrictions"
      return redirect_to :back
    end

    if target.vat_code_required_geo? && delete_vat_id
      flash[:warn] = "The VAT ID cannot be deleted from this account because it is required given their geography"
      return redirect_to :back
    end

    if !vat_id.present? && !delete_vat_id
      flash[:warn] = "No VAT ID was provided to update"
      return redirect_to :back
    end

    if vat_id.present? && delete_vat_id
      flash[:warn] = "Cannot set a VAT ID and delete it at the same time. Choose one or the other."
      return redirect_to :back
    end

    vat_id = nil if delete_vat_id
    if !target.feature_flag_enabled?(:read_billing_information_from_contacts, default: false) && target.billing_contact.persisted?
      target.billing_contact.update!(vat_code: vat_id)
    elsif !target.feature_flag_enabled?(:read_billing_information_from_contacts, default: false)
      errors << "Couldn't update VAT id on billing contact because account has no billing information on file"
    end
    if customer = target.customer
      customer.update!(vat_code: vat_id)
    else
      errors << "Couldn't update customer VAT id because account has no customer on file"
    end
    if errors.any?
      flash[:warn] = errors.join(", and ")
    else
      flash[:notice] = "VAT ID #{delete_vat_id ? "deleted" : "updated"} successfully"
    end
    redirect_to :back
  end
end
