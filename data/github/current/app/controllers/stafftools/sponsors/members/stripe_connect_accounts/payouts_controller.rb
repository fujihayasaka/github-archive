# typed: true
# frozen_string_literal: true

module Stafftools::Sponsors::Members
  class StripeConnectAccounts::PayoutsController < StripeConnectAccountsController
    include Stafftools::TradeCompliance::SharedControllerMethods

    before_action :staff_note_required, only: [:create]
    before_action :ensure_target_not_restricted, only: [:create]

    def create
      stripe_connect_account.create_payout!(actor: current_user, reason: params[:reason])
      flash[:notice] = "Successfully made a manual payout."
      redirect_to stafftools_sponsors_member_path(this_sponsorable)
    rescue Stripe::APIConnectionError, Stripe::StripeError => error
      flash[:error] = "Failed to issue manual payout: #{error.message}."
      redirect_to stafftools_sponsors_member_path(this_sponsorable)
    end

    private

    def staff_note_required
      if params[:reason].blank?
        flash[:error] = "Please enter a reason for manually issuing a payout."
        redirect_to stafftools_sponsors_member_path(this_sponsorable)
      end
    end

    def target
      this_sponsorable
    end
  end
end
