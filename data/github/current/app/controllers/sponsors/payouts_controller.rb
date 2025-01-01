# typed: strict
# frozen_string_literal: true

class Sponsors::PayoutsController < ApplicationController
  extend T::Sig
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program
  before_action :non_waitlisted_sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  stylesheet_bundle :sponsors

  sig { void }
  def index
    stripe_account = active_stripe_account
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end

    respond_to do |format|
      format.html do
        if request.xhr?
          payout_response = if !listing.uses_fiscal_host? && stripe_account
            stripe_account.latest_payout
          end

          estimated_payout_amount = if listing.uses_fiscal_host?
            listing.active_stripe_account_estimated_last_payout_balance
          end

          error = if payout_response && !payout_response.success?
            "Could not get your latest payout at this time. Please try again later."
          elsif !listing.uses_fiscal_host? && stripe_account.blank?
            "Create a Stripe Connect account to receive payouts."
          end

          render Sponsors::Payouts::LastPayoutComponent.new(
            sponsors_listing: listing,
            payout: payout_response&.result,
            error: error,
            stripe_account: stripe_account,
            estimated_payout_amount: estimated_payout_amount,
            disable_stripe_links: disable_stripe_links?
          ), layout: false
        else
          render "sponsors/payouts/index", locals: {
            sponsorable: sponsorable,
            sponsors_listing: listing,
            stripe_balance: listing.active_stripe_account_balance,
            disable_stripe_links: disable_stripe_links?
          }
        end
      end
    end
  end

  private

  sig { returns T::Boolean }
  def disable_stripe_links?
    listing = T.must_because(sponsorable_sponsors_listing) do
      "#non_waitlisted_sponsors_listing_required ensures non-nil"
    end
    return false if listing.adminable_by?(current_user)
    current_user.can_admin_sponsors_listings?
  end

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
