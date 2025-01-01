# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Overview::Statuses::StripeConnectComponent < ApplicationComponent
  include Sponsors::Dashboard::Overview::Statuses::ViewComponentMethods

  sig { override.params(sponsors_listing: SponsorsListing, billing_enabled: T::Boolean).void }
  def initialize(sponsors_listing:, billing_enabled: GitHub.billing_enabled?)
    @sponsors_listing = sponsors_listing
    @billing_enabled = billing_enabled
  end

  sig { override.returns(T::Boolean) }
  def render?
    stripe_eligible?
  end

  sig { override.returns(T::Boolean) }
  memoize def step_complete?
    stripe_accounts_edit_component.step_complete?
  end

  private

  sig { returns(Sponsors::StripeAccounts::EditComponent) }
  memoize def stripe_accounts_edit_component
    Sponsors::StripeAccounts::EditComponent.new(
      sponsors_listing: sponsors_listing,
    )
  end

  sig { returns(T::Boolean) }
  memoize def stripe_eligible?
    return false unless @billing_enabled
    return false if sponsors_listing.disabled?
    return true if sponsors_listing.active_stripe_connect_account
    return true if sponsors_listing.eligible_for_stripe_taxes?

    sponsors_listing.eligible_for_stripe_connect? && !sponsorable.needs_personal_profile?
  end
end
