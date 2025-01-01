# typed: strict
# frozen_string_literal: true

module GitHub::Billing
  module StripeWebhook
    class PayoutCreated
      sig { returns(::Stripe::Event) }
      attr_reader :event

      sig { returns(::Stripe::Payout) }
      attr_reader :payout

      # Public: Handle the payout created webhook payload
      sig { params(webhook: Billing::StripeWebhook).void }
      def self.perform(webhook)
        new(webhook).perform
      end

      # Public: Initializes a new PayoutCreated webhook handler
      sig { params(webhook: Billing::StripeWebhook).void }
      def initialize(webhook)
        @webhook = webhook
        @event = T.let(webhook.stripe_event, ::Stripe::Event)
        @payout = T.let(T.cast(@event.data.object, ::Stripe::Payout), ::Stripe::Payout)
      end

      # Public: Handle the payout created webhook payload
      sig { void }
      def perform
        GitHub.dogstats.increment("stripe.payout_created")
        GitHub.dogstats.count("stripe.payout_created.amount_in_cents", payout.amount)

        instrument_payout

        listing = stripe_connect_account.sponsors_listing
        last_payout_at = Time.at(payout.created).utc
        listing&.update!(last_payout_at: last_payout_at)

        transaction = Billing::PayoutsLedgerTransaction.new(stripe_connect_account)
        transaction.add_entry(
          transaction_type: :transfers_paid,
          amount_in_subunits: (-1 * payout.amount),
          currency_code: payout.currency.upcase,
          primary_reference_id: payout.id,
        )
        transaction.add_entry(
          transaction_type: :payout,
          amount_in_subunits: payout.amount,
          currency_code: payout.currency.upcase,
          primary_reference_id: payout.id,
        )
        transaction.save!
      end

      private

      sig { void }
      def instrument_payout
        # TODO Ask sponsors team about this
        GlobalInstrumenter.instrument("payout.bank_payout",
          sponsored_maintainer: stripe_connect_account.sponsorable,
          total_payout_amount_in_cents: payout.amount,
          destination_account_type: "stripe_connect",
          destination_account_id: event.account,
          status: "created",
          funding_instrument_type: payout.type,
          payout_id: payout.id,
        )
      end

      sig { returns(Billing::StripeConnect::Account) }
      def stripe_connect_account
        Billing::StripeConnect::Account.including_deleted.find_by!(stripe_account_id: event.account)
      end
    end
  end
end
