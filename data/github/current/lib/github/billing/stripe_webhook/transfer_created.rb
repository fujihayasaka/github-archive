# typed: strict
# frozen_string_literal: true

module GitHub::Billing
  module StripeWebhook
    class TransferCreated
      include GitHub::Memoizer

      sig { returns(::Stripe::Transfer) }
      attr_reader :transfer

      # Public: Handle the transfer created webhook payload
      sig { params(webhook: Billing::StripeWebhook).void }
      def self.perform(webhook)
        new(webhook).perform
      end

      # Public: Initializes a new TransferCreated webhook handler
      sig { params(webhook: Billing::StripeWebhook).void }
      def initialize(webhook)
        @webhook = webhook
        @event = T.let(webhook.stripe_event, Stripe::Event)
        @transfer = T.let(T.cast(@event.data.object, ::Stripe::Transfer), ::Stripe::Transfer)
      end

      # Public: Handle the transfer created webhook payload
      sig { void }
      def perform
        instrument_transfer
        transaction = Billing::PayoutsLedgerTransaction.new(stripe_connect_account)

        exceeded_match_limit_before = false

        transfer_metadata = transfer.metadata.to_h
        transaction.add_entry(
          transaction_type: :payment,
          amount_in_subunits: (-1 * payment_amount),
          currency_code: transfer.currency.upcase,
          primary_reference_id: zuora_transaction_id,
          stripe_charge_id: transfer_metadata[:stripe_charge_id],
          paypal_id: transfer_metadata[:paypal_id],
          credit_balance_adjustment_number: transfer_metadata[:credit_balance_adjustment_number],
          billing_transaction_id: billing_transaction&.id,
          sponsors_listing_id: sponsorship_recipient_listing_id,
        )

        if matched?
          exceeded_match_limit_before = sponsors_listing.reached_match_limit?

          transaction.add_entry(
            transaction_type: :github_match,
            amount_in_subunits: (-1 * match_amount),
            currency_code: transfer.currency.upcase,
            primary_reference_id: zuora_transaction_id,
            billing_transaction_id: billing_transaction&.id,
            sponsors_listing_id: sponsorship_recipient_listing_id,
          )
          GitHub.dogstats.increment("billing.sponsors.match")
        end

        transaction.add_entry(
          transaction_type: :transfer,
          amount_in_subunits: transfer.amount,
          currency_code: transfer.currency.upcase,
          primary_reference_id: transfer.id,
          zuora_transaction_id: zuora_transaction_id,
          billing_transaction_id: billing_transaction&.id,
          sponsors_listing_id: sponsorship_recipient_listing_id,
        )

        transaction.save!

        update_match_limit_reached(exceeded_match_limit_before)
      end

      private

      sig { params(exceeded_match_limit_before: T::Boolean).void }
      def update_match_limit_reached(exceeded_match_limit_before)
        if !exceeded_match_limit_before && matched?
          sponsors_listing.reset_total_match_in_cents!

          if sponsors_listing.reached_match_limit?
            # Store when the match limit was reached at.
            # See SponsorsListing#record_match_limit_reached for other
            # instrumentation that occurs when a listing hits the match limit.
            sponsors_listing.touch(:match_limit_reached_at)
          end
        end
      end

      sig { void }
      def instrument_transfer
        GlobalInstrumenter.instrument("payout.transfer", {
          account: transfer_from_account,
          total_transfer_amount_in_cents: transfer.amount,
          match_amount_in_cents: match_amount,
          sponsorship_amount_in_cents: payment_amount,
          destination_account_type: "stripe_connect",
          destination_account_id: transfer.destination,
          payment_gateway: payment_gateway,
          matched: (match_amount > 0),
        })
      end

      sig { returns(Integer) }
      def payment_amount
        transfer.metadata["payment_amount"].to_i
      end

      # Private: The Sponsors listing ID for the maintainer who is being sponsored.
      # Note this is not necessarily the same listing as what's associated with the
      # Stripe account. The Stripe account could be tied to a fiscal host's listing
      # while the sponsorship was for a maintainer who uses that fiscal host.
      sig { returns(T.nilable(T.any(String, Integer))) }
      memoize def sponsorship_recipient_listing_id
        transfer.metadata[:sponsors_listing_id]
      end

      # Private: Returns the Sponsors listing for use checking whether the GitHub matching limit
      # has been reached.
      sig { returns(SponsorsListing) }
      memoize def sponsors_listing
        if sponsorship_recipient_listing_id
          SponsorsListing.find(T.must(sponsorship_recipient_listing_id))
        else
          # If no listing was set in the Stripe metadata for the transfer, fall back to
          # whatever listing the Stripe account is associated with:
          T.must(stripe_connect_account.sponsors_listing)
        end
      end

      sig { returns(T.nilable(T.any(::User, Billing::DeadUser))) }
      def transfer_from_account
        User.find_by(id: transfer.metadata["sponsor_id"]) || billing_transaction&.user
      end

      sig { returns(String) }
      def payment_gateway
        return "invoice" if invoiced?

        if billing_transaction&.payment_type&.to_sym == :paypal
          "paypal"
        else
          "stripe"
        end
      end

      sig { returns(T.nilable(Billing::BillingTransaction)) }
      memoize def billing_transaction
        Billing::BillingTransaction.find_by(
          platform_transaction_id: zuora_transaction_id
        )
      end

      sig { returns(Integer) }
      def match_amount
        transfer.metadata["match_amount"].to_i
      end

      sig { returns(T::Boolean) }
      def matched?
        match_amount.positive?
      end

      sig { returns(T.nilable(String)) }
      def stripe_charge_id
        transfer.metadata["stripe_charge_id"]
      end

      sig { returns(String) }
      def zuora_transaction_id
        transfer.transfer_group
      end

      sig { returns(Billing::StripeConnect::Account) }
      memoize def stripe_connect_account
        Billing::StripeConnect::Account.including_deleted.find_by!(
          stripe_account_id: transfer.destination
        )
      end

      sig { returns(T.nilable(Integer)) }
      def invoiced_sponsorship_transfer_id
        transfer.metadata["invoiced_sponsorship_transfer_id"]
      end

      sig { returns(T::Boolean) }
      def invoiced?
        invoiced_sponsorship_transfer_id.present?
      end
    end
  end
end
