# typed: true
# frozen_string_literal: true

module Stafftools::Sponsors::Members
  class StripeConnectAccounts::PayoutTogglesController < StripeConnectAccountsController
    include Stafftools::TradeCompliance::SharedControllerMethods

    before_action :staff_note_required, only: [:destroy]
    before_action :ensure_target_not_restricted, only: [:create]

    def create
      stripe_connect_account.enable_payouts!(actor: current_user)
      flash[:notice] = "Enabled payouts for #{this_sponsorable.login}."
      redirect_to stafftools_sponsors_member_path(this_sponsorable)
    rescue Stripe::APIConnectionError, Stripe::StripeError => error
      flash[:error] = "Failed to enable payouts: #{error.message}"
      redirect_to stafftools_sponsors_member_path(this_sponsorable)
    end

    def destroy
      ApplicationRecord::Domain::Sponsors.transaction do
        stripe_connect_account.disable_payouts!(
          actor: current_user,
          reason: params[:disable_reason],
        )
        this_listing.staff_notes.create!(
          note: params[:disable_reason],
          user: current_user
        )
      end
      flash[:notice] = "Disabled payouts for #{this_sponsorable.login}."
      redirect_to stafftools_sponsors_member_path(this_sponsorable)
    rescue Stripe::APIConnectionError, Stripe::StripeError => error
      flash[:error] = "Failed to disable payouts: #{error.message}"
      redirect_to stafftools_sponsors_member_path(this_sponsorable)
    end

    private

    def staff_note_required
      if params[:disable_reason].blank?
        flash[:error] = "Please enter a reason for disabling payouts"
        redirect_to stafftools_sponsors_member_path(this_sponsorable)
      end
    end

    def target
      this_sponsorable
    end
  end
end
