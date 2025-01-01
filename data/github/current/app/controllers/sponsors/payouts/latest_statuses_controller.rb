# typed: strict
# frozen_string_literal: true

class Sponsors::Payouts::LatestStatusesController < ApplicationController
  include Sponsors::AdminableControllerValidations

  before_action :require_acceptance_into_sponsors_program
  before_action :non_waitlisted_sponsors_listing_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    only: [:show]

  stylesheet_bundle :sponsors

  # The latest payout status is loaded asychronously through this action because the
  # `StripeConnect::Account#latest_payout_failed?` method makes an API call to Stripe. We don't want to delay
  # rendering the page or render a 500 if there is something wrong with the API call to Stripe.
  sig { void }
  def show
    stripe_account = active_stripe_account
    return head(:ok) unless stripe_account

    sponsorable = T.must_because(self.sponsorable) { "#sponsorable_required ensures non-nil" }
    render "sponsors/payouts/latest_statuses/show", layout: false,
      locals: {
        latest_payout_failed: stripe_account.latest_payout_failed?,
        sponsorable_login: sponsorable.login
      }
  end

  private

  sig { returns T.any(Symbol, GitHubSponsors::Types::Sponsorable) }
  def target_for_conditional_access
    sponsorable || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
