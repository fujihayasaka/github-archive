# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::StripeAccountsComponent < ApplicationComponent
  def initialize(sponsors_listing:, stripe_accounts:, disable_stripe_links: false)
    @sponsors_listing = sponsors_listing
    @stripe_accounts = stripe_accounts
    @disable_stripe_links = disable_stripe_links
  end

  private

  attr_reader :sponsors_listing, :stripe_accounts

  delegate :sponsorable_login, to: :sponsors_listing

  def render?
    return false if sponsors_listing.disabled?
    stripe_accounts.any? || !sponsors_listing.uses_fiscal_host?
  end

  memoize def can_manage_stripe?
    !sponsors_listing.uses_fiscal_host?
  end

  def stripe_account_display_name(stripe_account)
    stripe_account.email.presence || stripe_account.stripe_account_id
  end

  def hide_stripe_link?
    @disable_stripe_links
  end
end
