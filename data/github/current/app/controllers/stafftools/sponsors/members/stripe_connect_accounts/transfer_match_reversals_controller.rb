# typed: true
# frozen_string_literal: true

module Stafftools::Sponsors::Members
  class StripeConnectAccounts::TransferMatchReversalsController < StripeConnectAccountsController
    before_action :ensure_valid_reversal_amount
    before_action :ensure_stripe_transfer_id

    def create
      begin
        ::Billing::Stripe::TransferMatchReversal.perform(
          stripe_account: stripe_connect_account,
          transfer_id: params[:stripe_transfer_id],
          match_amount_to_reverse: calculated_match_amount_to_reverse,
        )
        flash[:notice] = "#{params[:match_amount_to_reverse]} reversed, transfer was already fully reversed, or transfer no longer exists."
      rescue ::Stripe::InvalidRequestError, ::Stripe::APIError => e
        Failbot.report(e)
        flash[:error] = "There was an error reversing this match."
      rescue ::Billing::Stripe::TransferMatchReversal::DestinationMismatchError,
            ::Billing::Stripe::TransferMatchReversal::NotEnoughRemainingMatchError,
            ::Billing::Stripe::TransferMatchReversal::AlreadyPaidOutError => e
        flash[:error] = e
      end

      redirect_back fallback_location: stafftools_sponsors_member_path(this_sponsorable)
    end

    private

    def ensure_valid_reversal_amount
      if calculated_match_amount_to_reverse <= 0
        flash[:error] = "Reversal amount needs to be a number and greater than zero"
        redirect_back fallback_location: stafftools_sponsors_member_path(this_sponsorable)
      end
    end

    def ensure_stripe_transfer_id
      unless params[:stripe_transfer_id]
        flash[:error] = "Stripe transfer ID must be present"
        redirect_back fallback_location: stafftools_sponsors_member_path(this_sponsorable)
      end
    end

    memoize def calculated_match_amount_to_reverse
      ::Billing::Money.parse(params[:match_amount_to_reverse])
    end
  end
end
