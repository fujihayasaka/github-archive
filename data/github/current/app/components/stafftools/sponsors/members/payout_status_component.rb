# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Members::PayoutStatusComponent < ApplicationComponent
  sig { params(stripe_account: T.nilable(Billing::StripeConnect::Account)).void }
  def initialize(stripe_account:)
    @stripe_account = stripe_account
  end

  private

  sig { returns T.any(String, Symbol) }
  def octicon
    if !payouts_enabled?
      :x
    elsif !charges_enabled?
      "circle-slash"
    elsif automated_payouts_disabled?
      :lock
    else
      :check
    end
  end

  sig { returns({ icon: Symbol, text: String }) }
  memoize def colors
    if !payouts_enabled? || !charges_enabled?
      {
        icon: :danger,
        text: "color-fg-danger",
      }
    elsif automated_payouts_disabled?
      {
        icon: :attention,
        text: "color-fg-attention",
      }
    else
      {
        icon: :success,
        text: "color-fg-success",
      }
    end
  end

  sig { returns String }
  def label
    if !payouts_enabled?
      "Not enabled"
    elsif !charges_enabled?
      "Disabled"
    elsif automated_payouts_disabled?
      "Manual"
    else
      interval&.titleize || "Unknown"
    end
  end

  sig { returns T.nilable(String) }
  def interval
    @stripe_account&.payout_interval
  end

  sig { returns T::Boolean }
  def payouts_enabled?
    return false unless @stripe_account
    @stripe_account.payouts_enabled?
  end

  sig { returns T::Boolean }
  def charges_enabled?
    return false unless @stripe_account
    @stripe_account.charges_enabled?
  end

  sig { returns T::Boolean }
  memoize def automated_payouts_disabled?
    payouts_enabled? && T.must(@stripe_account).automated_payouts_disabled?
  end
end
