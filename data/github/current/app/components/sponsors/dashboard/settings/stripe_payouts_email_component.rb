# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::Settings::StripePayoutsEmailComponent < ApplicationComponent
  def initialize(sponsorable:, disable_stripe_links: false)
    @sponsorable = sponsorable
    @listing = sponsorable&.sponsors_listing
    @disable_stripe_links = disable_stripe_links
  end

  private

  attr_reader :sponsorable

  def render?
    GitHub.sponsors_enabled? && @listing&.stripe_transfers_enabled? && !@listing.uses_fiscal_host?
  end

  memoize def stripe_account
    @listing.stripe_transfer_account
  end

  def stripe_connect_email
    stripe_account.email
  end

  def hide_stripe_link?
    @disable_stripe_links
  end
end
