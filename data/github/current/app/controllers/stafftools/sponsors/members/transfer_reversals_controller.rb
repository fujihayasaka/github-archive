# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::TransferReversalsController < Stafftools::SponsorsController
  before_action :stripe_connect_account_required
  before_action :ensure_stripe_transfer_id

  def create
    payment_amount_reversed = Billing::Money.parse(params[:payment_amount_reversed]).cents
    match_amount_reversed = Billing::Money.parse(params[:match_amount_reversed]).cents

    result = Billing::Stripe::TransferReversal.perform(
      stripe_transfer_id: params[:stripe_transfer_id],
      stripe_refund_id: params[:stripe_refund_id],
      zuora_refund_id: params[:zuora_refund_id],
      payment_amount_to_reverse: payment_amount_reversed,
      match_amount_to_reverse: match_amount_reversed,
    )

    if result.success?
      flash[:notice] = result.message
      if notify_sponsorable?(result)
        SponsorsTransactionReversalNotificationJob.perform_later(
          sponsorable: this_sponsorable,
          sponsor: sponsor,
          stripe_account: stripe_account
        )
      end
    else
      flash[:error] = result.message
    end

    redirect_back fallback_location: stafftools_sponsors_member_path(this_sponsorable)
  end

  private

  def ensure_stripe_transfer_id
    unless params[:stripe_transfer_id]
      flash[:error] = "Stripe transfer ID must be present"
      redirect_back fallback_location: stafftools_sponsors_member_path(this_sponsorable)
    end
  end

  def notify_sponsorable?(result)
    params[:notify_sponsorable] == "1" && result.message&.include?("reversed for Stripe transfer #{params[:stripe_transfer_id]}")
  end

  def sponsor
    User.find_by(id: params[:sponsor_id]) if params[:sponsor_id]
  end

  def stripe_account
    Billing::StripeConnect::Account.find_by(id: params[:stripe_account_id]) if params[:stripe_account_id]
  end
end
