# typed: strict
# frozen_string_literal: true

class Sponsors::StripeAccounts::ActivationsController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :non_waitlisted_sponsors_listing_required
  before_action :require_acceptance_into_sponsors_program
  before_action :ensure_not_fiscally_hosted, only: [:create]

  sig { void }
  def create
    old_active_stripe_account = this_listing.active_stripe_connect_account
    enable_auto_payouts = if old_active_stripe_account
      !old_active_stripe_account.automated_payouts_disabled?
    else
      false
    end

    if account.activate
      setup_delay_in_minutes = 0
      if enable_auto_payouts
        account.enable_payouts(actor: current_user)
        setup_delay_in_minutes = 5 # give payout enabling time to run, to avoid lock contention
      end
      SetupStripeConnectAccountJob.set(wait: setup_delay_in_minutes.minutes)
        .perform_later(this_listing, existing_stripe_account: account)
      flash[:notice] = "Stripe Connect account successfully activated!"
    else
      flash[:error] = "Failed to activate Stripe Connect account, please try again later."
    end

    redirect_back fallback_location: sponsorable_dashboard_settings_path(sponsorable)
  end

  private

  sig { returns SponsorsListing }
  def this_listing
    T.must_because(sponsorable_sponsors_listing) { "#non_waitlisted_sponsors_listing_required ensures non-nil" }
  end

  sig { returns Billing::StripeConnect::Account }
  memoize def account
    this_listing.stripe_connect_accounts.find_by!(stripe_account_id: params[:stripe_account_id])
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
