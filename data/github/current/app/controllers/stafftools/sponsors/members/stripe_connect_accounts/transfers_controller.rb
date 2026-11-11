# typed: true
# frozen_string_literal: true

module Stafftools::Sponsors::Members
  class StripeConnectAccounts::TransfersController < StripeConnectAccountsController
    layout "application"

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
      ApplicationRecord::Billing,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    def index
      render "stafftools/sponsors/members/stripe_connect_accounts/transfers/index", locals: {
        sponsors_listing: this_listing,
        stripe_account: stripe_connect_account,
      }
    end

    def create
      result = Billing::Stripe::ManualTransfer.perform(**manual_transfer_params)

      if result.success?
        flash[:notice] = result.message
      else
        flash[:error] = result.message
      end

      redirect_back fallback_location: stafftools_sponsors_member_path(this_sponsorable)
    end

    private

    def manual_transfer_params
      payment_amount = Billing::Money.parse(params[:payment_amount]).cents
      match_amount   = Billing::Money.parse(params[:match_amount]).cents

      transfer_params = {
        payment_amount: payment_amount,
        match_amount: match_amount,
        currency: params[:currency],
        transfer_group: params[:transfer_group],
        stripe_charge_id: params[:stripe_charge_id],
      }.reject { |_key, value| value.blank? }

      transfer_params.merge(
        stripe_account_id: stripe_connect_account.stripe_account_id,
        sponsors_listing_id: this_listing.id,
      )
    end
  end
end
