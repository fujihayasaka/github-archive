# typed: strict
# frozen_string_literal: true

class Stafftools::Sponsors::Members::Transfers::ReverseTransferAndRefundPaymentFormComponent < ApplicationComponent
  extend T::Sig

  # sponsorable_login - String login for the User or Organization who received the transfer
  sig do
    params(
      transfer: Billing::Stripe::Transfer,
      stripe_account: Billing::StripeConnect::Account,
      sponsorable_login: String,
      billing_transaction: T.nilable(Billing::BillingTransaction),
    ).void
  end
  def initialize(transfer:, stripe_account:, sponsorable_login:, billing_transaction:)
    @transfer = transfer
    @stripe_account = stripe_account
    @sponsorable_login = sponsorable_login
    @billing_transaction = billing_transaction
  end

  private

  sig { returns(Billing::Stripe::Transfer) }
  attr_reader :transfer

  sig { returns(Billing::StripeConnect::Account) }
  attr_reader :stripe_account

  sig { returns(String) }
  attr_reader :sponsorable_login

  sig { returns(T.nilable(Billing::BillingTransaction)) }
  attr_reader :billing_transaction

  sig { returns(T.nilable(T::Boolean)) }
  def render?
    transfer.transfer_group.present? && billing_transaction&.refundable?
  end

  sig { returns(Billing::Money) }
  memoize def payment_amount
    transfer.payment_amount
  end

  sig { returns(Billing::Money) }
  memoize def payment_reversal_amount
    transfer.payment_amount_reversed
  end

  sig { returns(Billing::Money) }
  def payment_amount_reversed
    payment_amount - payment_reversal_amount
  end

  sig { returns(Billing::Money) }
  memoize def match_amount
    transfer.match_amount
  end

  sig { returns(Billing::Money) }
  memoize def match_reversal_amount
    transfer.match_amount_reversed
  end

  sig { returns(Billing::Money) }
  def match_amount_reversed
    match_amount - match_reversal_amount
  end

  sig { returns(Billing::Money) }
  memoize def total_amount_to_reverse
    payment_amount_reversed + match_amount_reversed
  end

  sig { returns(T::Array[Stripe::Reversal]) }
  memoize def reversals
    transfer.reversals
  end

  sig { returns(String) }
  def notify_sponsorable_id
    "notify-refund-sponsorable-#{transfer.transfer_id}"
  end
end
