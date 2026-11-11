# typed: true
# frozen_string_literal: true

module Stafftools::Sponsors::Members
  class StripeConnectAccounts::DeactivationsController < StripeConnectAccountsController
    def create
      if params[:deactivate_confirm] == stripe_connect_account.stripe_account_id
        if stripe_connect_account.update(active: false)
          flash[:notice] = "Stripe Connect account #{stripe_connect_account} for #{this_sponsorable} " \
            "has been marked as inactive."
        else
          error = stripe_connect_account.errors.full_messages.join(", ")
          flash[:error] = "Could not mark Stripe account as inactive: #{error}"
        end
      else
        flash[:error] = "Please confirm marking #{this_sponsorable}'s Stripe Connect account as inactive."
      end

      redirect_to stafftools_sponsors_member_path(this_sponsorable)
    end
  end
end
