# typed: strict
# frozen_string_literal: true

class Sponsors::StripeAccounts::EditComponent < ApplicationComponent
  STATUS_ICON_WIDTH = "20px"

  sig { params(sponsors_listing: SponsorsListing).void }
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  sig { returns(T::Boolean) }
  memoize def step_complete?
    render? && completed_overall?
  end

  private

  sig { returns(SponsorsListing) }
  attr_reader :sponsors_listing

  delegate :sponsorable_login, to: :sponsors_listing

  sig { returns(T::Boolean) }
  def render?
    # If they have a Stripe account, always show the component so we can link to
    # their Stripe dashboard
    return true if stripe_account

    # If they aren't using a fiscal host, show the component so we can prompt them to make a Stripe
    # account. If they are using a fiscal host, they don't need a Stripe account because we expect
    # the fiscal host to maintain a Stripe account.
    !sponsors_listing.uses_fiscal_host?
  end

  sig { returns(T::Boolean) }
  memoize def show_stripe_tax_form_step?
    this_stripe_account = stripe_account
    return false unless this_stripe_account.present?
    this_stripe_account.w8_or_w9_verification_required?
  end

  sig { returns(T::Boolean) }
  memoize def organization?
    sponsors_listing.for_organization?
  end

  sig { returns(T::Boolean) }
  def completed_overall?
    stripe_identity_status_complete? && payouts_enabled? && stripe_w8_or_w9_verified?
  end

  sig { returns(T.nilable(String)) }
  memoize def current_identity_deadline
    deadline = stripe_account&.current_requirements_deadline
    format_datetime(deadline) if deadline
  end

  sig { params(datetime: ActiveSupport::TimeWithZone).returns(String) }
  def format_datetime(datetime)
    datetime.strftime("%b %d")
  end

  sig { returns(T::Boolean) }
  def identity_items_currently_due?
    this_stripe_account = stripe_account
    return false unless this_stripe_account.present?
    this_stripe_account.requirements_currently_due?
  end

  sig { returns(T::Boolean) }
  def identity_items_past_due?
    this_stripe_account = stripe_account
    return false unless this_stripe_account.present?
    this_stripe_account.requirements_past_due?
  end

  sig { returns(T::Boolean) }
  def identity_items_eventually_due?
    this_stripe_account = stripe_account
    return false unless this_stripe_account.present?
    this_stripe_account.requirements_eventually_due?
  end

  sig { returns(T::Boolean) }
  def payouts_enabled?
    this_stripe_account = stripe_account
    return false unless this_stripe_account.present?
    this_stripe_account.payouts_enabled?
  end

  sig { returns(T::Boolean) }
  def stripe_w8_or_w9_verified?
    return true unless show_stripe_tax_form_step?
    this_stripe_account = stripe_account
    return false unless this_stripe_account.present?
    this_stripe_account.w8_or_w9_verified?
  end

  sig { returns(T::Boolean) }
  def has_payout_option?
    this_stripe_account = stripe_account
    return false unless this_stripe_account.present?
    this_stripe_account.billing_country.present?
  end

  sig { returns(T::Boolean) }
  def has_stripe_account?
    stripe_account.present?
  end

  sig { returns(T::Boolean) }
  def has_unverified_payout_option?
    has_payout_option? && !payouts_enabled?
  end

  sig { returns(String) }
  def aggregate_status_icon
    if completed_overall?
      "check"
    elsif has_stripe_account?
      "clock"
    else
      "dot-fill"
    end
  end

  sig { returns(Symbol) }
  def aggregate_status_icon_color
    if completed_overall?
      :success
    else
      :attention
    end
  end

  sig { returns(String) }
  def stripe_account_status_icon
    if has_stripe_account?
      "check"
    else
      "dot-fill"
    end
  end

  sig { returns(Symbol) }
  def stripe_account_status_icon_color
    if has_stripe_account?
      :success
    else
      :attention
    end
  end

  sig { returns(T::Boolean) }
  def stripe_identity_status_complete?
    stripe_account_verified?
  end

  sig { returns(String) }
  def stripe_identity_status_icon
    if stripe_identity_status_complete?
      "check"
    elsif stripe_account_verified?
      "clock"
    else
      "alert"
    end
  end

  # Private: Used in Primer::Beta::Octicon, see https://primer.style/view-components/system-arguments#color.
  sig { returns(Symbol) }
  def stripe_identity_status_icon_color
    if stripe_identity_status_complete?
      :success
    elsif stripe_account_verified?
      :attention
    else
      :danger
    end
  end

  sig { returns(T::Boolean) }
  def stripe_account_verified?
    this_stripe_account = stripe_account
    return false unless this_stripe_account.present?
    this_stripe_account.verified_verification_status?
  end

  sig { returns(T.nilable(Billing::StripeConnect::Account)) }
  memoize def stripe_account
    sponsors_listing.active_stripe_connect_account
  end
end
