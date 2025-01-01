# typed: true
# frozen_string_literal: true

module Stafftools::Sponsors::Members
  class StripeConnectAccounts::SyncsController < StripeConnectAccountsController
    def create
      begin
        Sponsors::SyncStripeAccountDetails.call(stripe_connect_account)
        flash[:notice] = if stripe_connect_account.deleted?
          "@#{this_sponsorable}'s Stripe Connect account #{stripe_connect_account} no longer exists on Stripe and " \
            "has been marked as deleted on GitHub."
        else
          "Stripe details synced for @#{this_sponsorable}'s Stripe Connect account #{stripe_connect_account}."
        end
      rescue ActiveRecord::RecordInvalid,
          Stripe::APIConnectionError,
          Billing::StripeConnect::Account::SyncError,
          Stripe::StripeError => e
        flash[:error] = e.message.presence || "Failed to sync Stripe details."
      end

      redirect_to stafftools_sponsors_member_path(this_sponsorable)
    end
  end
end
