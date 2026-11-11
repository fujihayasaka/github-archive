# typed: strict
# frozen_string_literal: true

module Billing
  module Stripe
    class TransferMatchReversal
      class DestinationMismatchError < StandardError; end
      class NotEnoughRemainingMatchError < StandardError; end
      class AlreadyPaidOutError < StandardError; end

      DESTINATION_MISMATCH_ERROR_MESSAGE = "This transfer's destination does not match the sponsorable's Stripe account."
      REMAINING_MATCH_ERROR_MESSAGE = "Entered value is greater than the remaining match amount."
      ALREADY_PAID_OUT_ERROR_MESSAGE = "This transfer has already been paid out, so matching cannot be reversed."

      # Public: Reverse all or part of a match from a previous stripe transfer
      sig do
        params(stripe_account: ::Billing::StripeConnect::Account, transfer_id: String, match_amount_to_reverse: ::Billing::Money).void
      end
      def self.perform(stripe_account:, transfer_id:, match_amount_to_reverse:)
        new(stripe_account: stripe_account, transfer_id: transfer_id, match_amount_to_reverse: match_amount_to_reverse).perform
      end

      # Initialze ::Billing::Stripe::TransferMatchReversal
      #
      # stripe_account           - The Billing::StripeConnect::Account that this reversal is for
      # transfer_id              - The ID to a Stripe::Transfer object we wish to reverse match for
      # match_amount_to_reverse: - The amount of the match we will be reversing
      sig do
        params(
          stripe_account: ::Billing::StripeConnect::Account,
          transfer_id: String,
          match_amount_to_reverse: ::Billing::Money,
        ).void
      end
      def initialize(stripe_account:, transfer_id:, match_amount_to_reverse:)
        @stripe_account          = stripe_account
        @transfer_id             = transfer_id
        @match_amount_to_reverse = match_amount_to_reverse
      end

      # Public: perform the match reversal
      # Raises NotEnoughRemainingMatchError if requested match reversal amount is more than the total match
      # left on the transfer
      sig { void }
      def perform
        if destination_mismatch?
          raise DestinationMismatchError.new(DESTINATION_MISMATCH_ERROR_MESSAGE)
        elsif already_paid_out?
          raise AlreadyPaidOutError.new(ALREADY_PAID_OUT_ERROR_MESSAGE)
        elsif (transfer.match_amount_reversed + match_amount_to_reverse) > transfer.match_amount
          raise NotEnoughRemainingMatchError.new(REMAINING_MATCH_ERROR_MESSAGE)
        else
          create_transfer_reversal
        end
      end

      private

      sig { returns(::Billing::StripeConnect::Account) }
      attr_reader :stripe_account

      sig { returns(String) }
      attr_reader :transfer_id

      sig { returns(::Billing::Money) }
      attr_reader :match_amount_to_reverse

      # Internal: Retrieve the parent transfer object from Stripe
      # Raises Stripe::APIError in several situations
      sig { returns(::Stripe::Transfer) }
      def stripe_transfer
        @_stripe_transfer ||= T.let(::Stripe::Transfer.retrieve(transfer_id), T.nilable(::Stripe::Transfer))
      end

      # Internal: Initialize our representation of a Stripe::Transfer
      sig { returns(::Billing::Stripe::Transfer) }
      def transfer
        @transfer ||= T.let(::Billing::Stripe::Transfer.from_transfer(stripe_transfer), T.nilable(::Billing::Stripe::Transfer))
      end

      # Internal: Is this transfer already paid out to the user?
      sig { returns(T::Boolean) }
      def already_paid_out?
        payout_created_at = stripe_account.latest_payout_created
        transfer_created_at = transfer.transferred_at
        return false unless payout_created_at && transfer_created_at

        payout_created_at > transfer_created_at
      end

      # Internal: Does the destination of this transfer not match the account we
      #           want to reverse the match for?
      sig { returns(T::Boolean) }
      def destination_mismatch?
        stripe_account.stripe_account_id != stripe_transfer.destination
      end

      # Internal: Create a transfer reversal in Stripe
      # Raises Stripe::APIError in several situations
      # Raises Stripe::InvalidRequestError if transfer is fully reversed or doesn't exist anymore
      sig { void }
      def create_transfer_reversal
        ::Stripe::Transfer.create_reversal(
          transfer_id,
          amount: match_amount_to_reverse.fractional,
          metadata: {
            payment_amount_reversed: 0,
            match_amount_reversed: match_amount_to_reverse.fractional,
            sponsors_listing_id: transfer.sponsors_listing_id,
            # The two key/value pairs below do not explicitly need to be included.
            # They are listed here to be explicting about them having a `nil` value,
            # not that they were forgotten.
            stripe_refund_id: nil,
            zuora_refund_id: nil,
          },
        )
      end
    end
  end
end
