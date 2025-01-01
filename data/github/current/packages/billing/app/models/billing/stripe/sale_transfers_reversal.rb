# typed: strict
# frozen_string_literal: true

module Billing
  module Stripe
    # Public: Allows Zuora payment reversal, retrieving all transfers from a sale transfer group and
    # reversing each one by calling Billing::Stripe::TransfersReversal.
    class SaleTransfersReversal
      extend T::Sig

      TransferNotFound = Class.new(StandardError)

      # Public: Reverse a transfer to a Stripe Connect account
      sig do
        params(
          sale_transaction_id: T.nilable(String),
          stripe_refund_id: T.nilable(String),
          zuora_refund_id: T.nilable(String),
          payment_amount_to_reverse: T.nilable(::Billing::Types::Numeric),
          match_amount_to_reverse: T.nilable(::Billing::Types::Numeric)
        ).void
      end
      def self.perform(sale_transaction_id:, stripe_refund_id:, zuora_refund_id:, payment_amount_to_reverse: nil, match_amount_to_reverse: nil)
        new(
          sale_transaction_id: sale_transaction_id,
          stripe_refund_id: stripe_refund_id,
          zuora_refund_id: zuora_refund_id,
          payment_amount_to_reverse: payment_amount_to_reverse,
          match_amount_to_reverse: match_amount_to_reverse
        ).perform
      end

      # Public: Initialize a new ReverseTransfer object
      #
      # sale_transaction_id       - The id of the original Zuora payment
      # stripe_refund_id          - The Stripe id of the refund causing this reversal
      # zuora_refund_id           - The Zuora id of the refund causing this reversal
      # payment_amount_to_reverse - The amount of the cardholder's payment to reverse
      #                             if doing a partial reversal (optional)
      # match_amount_to_reverse   - The amount of the GitHub match to reverse if
      #                             doing a partial reversal (optional)
      sig do
        params(
          sale_transaction_id: T.nilable(String),
          stripe_refund_id: T.nilable(String),
          zuora_refund_id: T.nilable(String),
          payment_amount_to_reverse: T.nilable(::Billing::Types::Numeric),
          match_amount_to_reverse: T.nilable(::Billing::Types::Numeric)
        ).void
      end
      def initialize(sale_transaction_id:, stripe_refund_id:, zuora_refund_id:, payment_amount_to_reverse: nil, match_amount_to_reverse: nil)
        @sale_transaction_id = sale_transaction_id
        @stripe_refund_id = stripe_refund_id
        @zuora_refund_id = zuora_refund_id
        @total_payment_amount_to_reverse = payment_amount_to_reverse
        @total_match_amount_to_reverse = match_amount_to_reverse
      end

      # Public: Reverse transfers to maintainers Stripe Connect accounts
      sig { void }
      def perform
        transfers_to_reverse.each do |stripe_transfer|
          transfer_id = stripe_transfer.id
          next unless transfer_id
          Billing::Stripe::TransferReversal.perform(
            stripe_transfer_id: transfer_id,
            stripe_refund_id: stripe_refund_id,
            zuora_refund_id: zuora_refund_id,
            payment_amount_to_reverse: total_payment_amount_to_reverse,
            match_amount_to_reverse: total_match_amount_to_reverse,
          )
        end
      end

      private

      sig { returns(T.nilable(String)) }
      attr_reader :sale_transaction_id

      sig { returns(T.nilable(String)) }
      attr_reader :stripe_refund_id

      sig { returns(T.nilable(String)) }
      attr_reader :zuora_refund_id

      sig { returns(T.nilable(::Billing::Types::Numeric)) }
      attr_reader :total_payment_amount_to_reverse

      sig { returns(T.nilable(::Billing::Types::Numeric)) }
      attr_reader :total_match_amount_to_reverse

      sig { returns(T::Array[Billing::Stripe::Transfer]) }
      def transfers_to_reverse
        if sale_transaction_id.nil?
          GitHub.dogstats.increment("stripe.transfer_reversal.failed")
          raise TransferNotFound.new("Reversal failed: An original payment ID is required ")
        end

        transfers = Billing::Stripe::Transfer.list(transfer_group: sale_transaction_id, limit: nil)
        if transfers.empty?
          GitHub.dogstats.increment("stripe.transfer_reversal.failed")
          raise TransferNotFound.new("Reversal failed: Transfer not found")
        end

        transfers
      end
    end
  end
end
