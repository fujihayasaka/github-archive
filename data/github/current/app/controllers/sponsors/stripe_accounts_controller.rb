# typed: strict
# frozen_string_literal: true

class Sponsors::StripeAccountsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program
  before_action :ensure_not_fiscally_hosted, only: [:create]

  layout "layouts/sponsors"

  stylesheet_bundle :sponsors

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show],
    optional: true

  sig { void }
  def show
    if account.details_submitted?
      redirect_to Stripe::Account.create_login_link(account.stripe_account_id).url
    else
      redirect_to account.stripe_onboarding_url!(
        refresh_url: sponsorable_stripe_account_url(sponsorable, account),
        return_url: edit_sponsorable_stripe_account_url(sponsorable, account),
      )
    end
  rescue Stripe::APIConnectionError
    redirect_to(sponsorable_dashboard_path(sponsorable))
  rescue Stripe::InvalidRequestError => e
    # we will get this error whenever we try to generate a login link
    # and the account hasn't finished onboarding.
    GitHub.dogstats.increment("stripe.invalid_request_error", tags: ["action:generate_link"])

    redirect_to account.stripe_onboarding_url!(
      refresh_url: sponsorable_stripe_account_url(sponsorable, account),
      return_url: edit_sponsorable_stripe_account_url(sponsorable, account),
    )
  end

  sig { void }
  def create
    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    unless sponsorable.within_sponsors_stripe_account_limit?
      flash[:error] = "You have reached the limit of Stripe Connect accounts for your " \
        "GitHub Sponsors profile. Please contact support to add another Stripe Connect account."
      return redirect_to(sponsorable_dashboard_settings_path(sponsorable))
    end

    new_stripe_account = this_listing.create_stripe_account!

    redirect_to new_stripe_account.stripe_onboarding_url!(
      refresh_url: sponsorable_stripe_account_url(sponsorable, new_stripe_account),
      return_url: edit_sponsorable_stripe_account_url(sponsorable, new_stripe_account),
    )
  end

  sig { void }
  def edit
    SetupStripeConnectAccountJob.perform_later(
      this_listing,
      existing_stripe_account: account,
    )

    flash[:notice] = "Your Stripe account has been created and is in the process of being verified!"
    redirect_path = if signup_complete?
      sponsorable_dashboard_path(sponsorable)
    else
      sponsorable_signup_path(sponsorable)
    end
    redirect_to redirect_path
  end

  sig { void }
  def destroy
    if account.deletable_by?(current_user) && this_listing.delete_stripe_account(account)
      flash[:notice] = "Your Stripe Connect account has been deleted."
    else
      flash[:error] = "Your Stripe Connect account could not be deleted. Please try again later or contact support."
    end

    redirect_to sponsorable_dashboard_settings_path(sponsorable)
  end

  private

  sig { returns SponsorsListing }
  def this_listing
    T.must_because(sponsorable_sponsors_listing) { "#non_waitlisted_sponsors_listing_required ensures non-nil" }
  end

  sig { returns Billing::StripeConnect::Account }
  def account
    this_listing.stripe_connect_accounts.find_by!(stripe_account_id: params[:id])
  end

  sig { returns T::Boolean }
  def signup_complete?
    !this_listing.draft?
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
