# typed: strict
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::DeleteStripeComponent < ApplicationComponent
  sig { params(sponsors_listing: SponsorsListing, stripe_account: Billing::StripeConnect::Account).void }
  def initialize(sponsors_listing:, stripe_account:)
    @sponsors_listing = sponsors_listing
    @stripe_account = stripe_account
  end

  private

  sig { returns(SponsorsListing) }
  attr_reader :sponsors_listing

  sig { returns(Billing::StripeConnect::Account) }
  attr_reader :stripe_account

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.sponsors_enabled?

    stripe_account.sponsors_listing_id == sponsors_listing.id
  end

  sig { returns(T.nilable(String)) }
  memoize def human_reason_delete_is_not_allowed
    return if allow_delete?
    case stripe_account.reason_delete_is_not_allowed
    when :active_account
      "You can't delete @#{sponsorable_login}'s only active Stripe Connect account."
    when :positive_balance
      "You cannot delete a Stripe Connect account that has a positive balance."
    when :has_received_money
      "You cannot delete this Stripe Connect account. Please reach out to support if you need further assistance."
    end
  end

  sig { returns(T::Boolean) }
  memoize def allow_delete?
    sponsorable = sponsors_listing.sponsorable
    return false unless sponsorable
    stripe_account.deletable_by?(sponsorable)
  end

  sig { returns(String) }
  def button_test_selector
    "delete-stripe-button-#{allow_delete? ? 'enable' : 'disabled'}"
  end

  sig { returns(String) }
  def sponsorable_login
    sponsors_listing.sponsorable_login
  end
end
