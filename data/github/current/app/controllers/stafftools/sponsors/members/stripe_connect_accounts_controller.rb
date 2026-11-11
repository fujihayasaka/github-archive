# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::StripeConnectAccountsController < Stafftools::SponsorsController
  before_action :require_stripe_connect_account
  skip_before_action :require_stripe_connect_account, if: :stripe_connect_accounts_create_action?

  def create
    stripe_account = Billing::StripeConnect::LinkAccount.call(
      stripe_account_id: params[:stripe_account_id],
      sponsors_listing: this_listing,
      actor: current_user,
    )
    flash[:notice] = "Stripe account #{stripe_account} is now linked to #{this_sponsorable}'s Sponsors account."
    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  rescue Billing::StripeConnect::LinkAccount::ValidationError,
         Billing::StripeConnect::LinkAccount::StripeSyncError => err
    flash[:error] = err.message
    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end

  def destroy
    if params[:delete_confirm] == stripe_connect_account.stripe_account_id
      if stripe_connect_account.deletable_by?(current_user) && this_listing.delete_stripe_account(stripe_connect_account)
        flash[:notice] = "Stripe Connect account #{stripe_connect_account} for #{this_sponsorable} has been deleted."
      else
        flash[:error] = "Could not delete #{this_sponsorable}'s Stripe Connect account."
      end
    else
      flash[:error] = "Could not delete #{this_sponsorable}'s Stripe Connect account."
    end

    redirect_to stafftools_sponsors_member_path(this_sponsorable)
  end

  protected

  def require_stripe_connect_account
    render_404 unless stripe_connect_account
  end

  memoize def stripe_connect_account
    id = params[:stripe_connect_account_id] || params[:id]
    this_listing.stripe_connect_accounts.find_by(stripe_account_id: id)
  end

  private

  def stripe_connect_accounts_create_action?
    params[:action] == "create" && params[:controller] == "stafftools/sponsors/members/stripe_connect_accounts"
  end
end
