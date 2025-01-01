# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::StripeTaxStatusComponent < ApplicationComponent
  StatusText = Struct.new(:label, :hint, :test_selector, :scheme, keyword_init: true)

  # listing - a SponsorsListing
  def initialize(listing:)
    @listing = listing
  end

  private

  attr_reader :listing

  def render?
    listing.present?
  end

  memoize def status_text
    if listing.uses_fiscal_host?
      StatusText.new(
        label: "Not applicable",
        hint: "No tax forms required because this maintainer uses a fiscal host",
        test_selector: "w8-not-required",
        scheme: :secondary
      )
    elsif listing.waiting_to_see_if_stripe_tax_verification_is_required?
      StatusText.new(
        label: "Waiting",
        hint: "Waiting for Stripe account to be created and synced",
        test_selector: "stripe-w8-waiting",
        scheme: :attention
      )
    elsif stripe_account.w8_or_w9_verified?
      StatusText.new(
        label: "Verified",
        hint: "Completed and verified on Stripe",
        test_selector: "stripe-w8-verified",
        scheme: :success
      )
    else
      StatusText.new(
        label: "Pending",
        hint: "Tax verification requested through Stripe but has not been verified",
        test_selector: "stripe-w8-pending",
        scheme: :attention
      )
    end
  end

  def stripe_account
    listing.active_stripe_connect_account
  end
end
