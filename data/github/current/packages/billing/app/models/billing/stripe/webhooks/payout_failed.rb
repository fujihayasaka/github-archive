# typed: strict
# frozen_string_literal: true

class Billing::Stripe::Webhooks::PayoutFailed
  # Public: Handle the payout failed webhook payload
  sig { params(webhook: Billing::StripeWebhook).void }
  def self.perform(webhook)
    new(webhook).perform
  end

  # Public: Initializes a new PayoutFailed webhook handler
  sig { params(webhook: Billing::StripeWebhook).void }
  def initialize(webhook)
    @webhook = webhook
    @event = T.let(webhook.stripe_event, ::Stripe::Event)
    @payout = T.let(T.cast(@event.data.object, ::Stripe::Payout), ::Stripe::Payout)
  end

  # Public: Handle the payout created webhook payload
  sig { void }
  def perform
    GitHub.dogstats.increment("stripe.payout_failed")
    GitHub.dogstats.count("stripe.payout_failed.amount_in_cents", payout.amount)
    instrument_payout

    transaction = Billing::PayoutsLedgerTransaction.new(stripe_connect_account)

    transaction.add_entry(
      transaction_type: :transfers_paid,
      amount_in_subunits: payout.amount,
      currency_code: payout.currency.upcase,
      primary_reference_id: payout.id,
    )
    transaction.add_entry(
      transaction_type: :payout_failure,
      amount_in_subunits: (-1 * payout.amount),
      currency_code: payout.currency.upcase,
      primary_reference_id: payout.id,
    )

    transaction.save!
  end

  private

  sig { returns(::Stripe::Payout) }
  attr_reader :payout

  sig { returns(::Stripe::Event) }
  attr_reader :event

  sig { void }
  def instrument_payout
    GlobalInstrumenter.instrument("payout.bank_payout", {
      sponsored_maintainer: stripe_connect_account.sponsorable,
      total_payout_amount_in_cents: payout.amount,
      destination_account_type: "stripe_connect",
      destination_account_id: event.account,
      status: "failed",
      funding_instrument_type: payout.type,
      payout_id: payout.id,
      failure_code: payout.failure_code,
    })
  end

  sig { returns(Billing::StripeConnect::Account) }
  def stripe_connect_account
    Billing::StripeConnect::Account.including_deleted.find_by!(
      stripe_account_id: event.account,
    )
  end
end
