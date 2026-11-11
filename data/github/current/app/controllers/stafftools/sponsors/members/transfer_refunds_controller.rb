# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::TransferRefundsController < Stafftools::SponsorsController
  before_action :stripe_connect_account_required
  before_action :ensure_stripe_transfer_id
  before_action :ensure_transaction_id

  def create
    ::Billing::ReverseTransferAndTransactionJob.perform_later(
      stripe_transfer_id: params[:stripe_transfer_id],
      transaction_id: params[:transaction_id],
      stripe_account_id: params[:stripe_account_id],
      sponsor_id: params[:sponsor_id],
      sponsorable: this_sponsorable,
      notify_sponsorable: notify_sponsorable?,
    )
    flash[:notice] = "Reverse transfer and payment has been queued up and will process in the background."
    redirect_back fallback_location: stafftools_sponsors_member_path(this_sponsorable)
  end

  private

  def ensure_stripe_transfer_id
    unless params[:stripe_transfer_id]
      flash[:error] = "Stripe transfer ID must be present"
      redirect_back fallback_location: stafftools_sponsors_member_path(this_sponsorable)
    end
  end

  def ensure_transaction_id
    unless params[:transaction_id]
      flash[:error] = "Transaction ID must be present"
      redirect_back fallback_location: stafftools_sponsors_member_path(this_sponsorable)
    end
  end

  def notify_sponsorable?
    params[:notify_sponsorable] == "1"
  end
end
