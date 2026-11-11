# typed: strict
# frozen_string_literal: true

module Billing
  module Stripe
    # Public: Allows reversing an entire or partial transfer in a Stripe Connect account.
    class TransferReversal
      include GitHub::Memoizer

      INTER_ACCOUNT_TRANSFER_KEY = :transfer_to

      TransferReversalError = Class.new(StandardError)
      TransferDoesNotExist = Class.new(TransferReversalError)
      TransferAlreadyReversed = Class.new(TransferReversalError)
      TransferReversalAmountIsZero = Class.new(TransferReversalError)
      InvalidRetransfer = Class.new(TransferReversalError)

      class Result
        sig { returns T::Boolean }
        attr_reader :success

        sig { returns T.nilable(String) }
        attr_reader :message

        alias_method :success?, :success

        # success – indicates the success of an operation
        # errors – optional error message
        sig { params(success: T::Boolean, message: T.nilable(String)).void }
        def initialize(success:, message:)
          @success = success
          @message = message
        end

        sig { params(message: T.nilable(String)).returns(Result) }
        def self.success(message: nil)
          new(success: true, message: message)
        end

        sig { params(message: T.nilable(String)).returns(Result) }
        def self.failure(message: nil)
          new(success: false, message: message)
        end
      end

      # Nested class responsible for calculating how much of the payment and
      # GitHub match should be reversed for each transfer
      class AmountToReverse
        sig { returns Transfer }
        attr_reader :transfer

        sig { returns Types::Numeric }
        attr_reader :transfer_payment_amount, :transfer_match_amount

        sig { returns Types::Numeric }
        attr_reader :max_payment_amount_to_reverse, :max_match_amount_to_reverse

        sig { returns T.nilable(T.any(String, Integer)) }
        attr_reader :sponsors_listing_id

        # max_payment_amount_to_reverse - The maximum payment amount to reverse (optional)
        # max_match_amount_to_reverse   - The maximum GitHub match amount to reverse (optional)
        sig do
          params(
            transfer: Transfer,
            max_payment_amount_to_reverse: T.nilable(Types::Numeric),
            max_match_amount_to_reverse: T.nilable(Types::Numeric)
          ).void
        end
        def initialize(transfer:, max_payment_amount_to_reverse: nil, max_match_amount_to_reverse: nil)
          @transfer = transfer
          @transfer_payment_amount = T.let(transfer.metadata[:payment_amount].to_i, Integer)
          @transfer_match_amount = T.let(transfer.metadata[:match_amount].to_i, Integer)
          @sponsors_listing_id = T.let(transfer.metadata[:sponsors_listing_id], T.nilable(T.any(String, Integer)))

          @max_payment_amount_to_reverse = T.let(max_payment_amount_to_reverse || transfer_payment_amount,
            Types::Numeric)
          @max_match_amount_to_reverse = T.let(max_match_amount_to_reverse || transfer_match_amount, Types::Numeric)
        end

        # Returns the amount of the payment to reverse
        sig { returns Types::Numeric }
        def payment_amount
          [max_payment_amount_to_reverse, payment_amount_reversible].min
        end

        # Returns the amount of the GitHub match to reverse
        sig { returns Types::Numeric }
        def match_amount
          [max_match_amount_to_reverse, match_amount_reversible].min
        end

        sig { returns T::Boolean }
        def full_amount?
          return false if reversals.present?
          payment_amount == payment_amount_reversible && match_amount == match_amount_reversible
        end

        private

        sig { returns Integer }
        def payment_amount_reversible
          transfer_payment_amount - reversals.sum do |reversal|
            reversal.metadata[:payment_amount_reversed].to_i
          end
        end

        sig { returns Integer }
        def match_amount_reversible
          transfer_match_amount - reversals.sum do |reversal|
            reversal.metadata[:match_amount_reversed].to_i
          end
        end

        sig { returns T::Array[::Stripe::Reversal] }
        def reversals
          transfer.reversals
        end
      end

      # Public: Reverse a transfer to a Stripe Connect account
      sig do
        params(
          stripe_transfer_id: String,
          stripe_refund_id: T.nilable(String),
          zuora_refund_id: T.nilable(String),
          payment_amount_to_reverse: T.nilable(Types::Numeric),
          match_amount_to_reverse: T.nilable(Types::Numeric),
          transfer_to: T.nilable(String)
        ).returns(Result)
      end
      def self.perform(
        stripe_transfer_id:,
        stripe_refund_id: nil,
        zuora_refund_id: nil,
        payment_amount_to_reverse: nil,
        match_amount_to_reverse: nil,
        transfer_to: nil
      )
        new(
          stripe_transfer_id: stripe_transfer_id,
          stripe_refund_id: stripe_refund_id,
          zuora_refund_id: zuora_refund_id,
          payment_amount_to_reverse: payment_amount_to_reverse,
          match_amount_to_reverse: match_amount_to_reverse,
          transfer_to: transfer_to
        ).perform
      end

      # Public: Initialize a new ReverseTransfer object
      #
      # stripe_transfer_id        - The id of the transfer to be refunded
      # stripe_refund_id          - The Stripe id of the refund causing this reversal (optional)
      # zuora_refund_id           - The Zuora id of the refund causing this reversal (optional)
      # payment_amount_to_reverse - The amount of the cardholder's payment to reverse
      #                             if doing a partial reversal (optional)
      # match_amount_to_reverse   - The amount of the GitHub match to reverse if
      #                             doing a partial reversal (optional)
      # transfer_to               - Stripe account id destination to re-transfer the funds (optional)
      sig do
        params(
          stripe_transfer_id: String,
          stripe_refund_id: T.nilable(String),
          zuora_refund_id: T.nilable(String),
          payment_amount_to_reverse: T.nilable(Types::Numeric),
          match_amount_to_reverse: T.nilable(Types::Numeric),
          transfer_to: T.nilable(String)
        ).void
      end
      def initialize(
        stripe_transfer_id:,
        stripe_refund_id: nil,
        zuora_refund_id: nil,
        payment_amount_to_reverse: nil,
        match_amount_to_reverse: nil,
        transfer_to: nil
      )
        @stripe_transfer_id = stripe_transfer_id
        @stripe_refund_id = stripe_refund_id
        @zuora_refund_id = zuora_refund_id
        @transfer_to = transfer_to

        @amount_to_reverse = T.let(AmountToReverse.new(
          transfer: stripe_transfer,
          max_payment_amount_to_reverse: payment_amount_to_reverse,
          max_match_amount_to_reverse: match_amount_to_reverse,
        ), AmountToReverse)
      end

      # Public: Reverse transfers to maintainers Stripe Connect accounts
      sig { returns Result }
      def perform
        validate!

        reverse_transfer(
          T.must(stripe_transfer.id),
          payment_amount_reversed: amount_to_reverse.payment_amount,
          match_amount_reversed: amount_to_reverse.match_amount,
          sponsors_listing_id: amount_to_reverse.sponsors_listing_id,
          transfer_to: transfer_to,
        )

      # InvalidRequestError means either the transfer is fully reversed or doesn't
      # exist anymore - both scenarios we count as a success since that means
      # that the maintainer does not have the money in their Connect account.
      # Mission accomplished.
      rescue TransferReversalAmountIsZero
        Result.success(message: "Stripe transfer reversal for #{stripe_transfer_id} was requested with 0 amount.")
      rescue TransferAlreadyReversed
        Result.success(message: "Stripe transfer #{stripe_transfer_id} was already fully reversed.")
      rescue ::Stripe::APIError => e
        Failbot.report(e, { "gh.billing.stripe_transfer.id" => stripe_transfer_id })
        Result.failure(message: "There was an error reversing Stripe transfer #{stripe_transfer_id}.")
      rescue TransferReversalError => e
        Result.failure(message: e.message)
      end

      private

      sig { returns String }
      attr_reader :stripe_transfer_id

      sig { returns T.nilable(String) }
      attr_reader :stripe_refund_id, :zuora_refund_id, :transfer_to

      sig { returns AmountToReverse }
      attr_reader :amount_to_reverse

      sig { void }
      def validate!
        if amount_to_reverse.payment_amount.zero? && amount_to_reverse.match_amount.zero?
          raise TransferAlreadyReversed
        end

        if transfer_to.present?
          validate_transfer_to!
        end
      end

      sig do
        params(
          stripe_transfer_id: String,
          payment_amount_reversed: Types::Numeric,
          match_amount_reversed: Types::Numeric,
          sponsors_listing_id: T.nilable(T.any(Integer, String)),
          transfer_to: T.nilable(String)
        ).returns(Result)
      end
      def reverse_transfer(stripe_transfer_id,
        payment_amount_reversed:,
        match_amount_reversed:,
        sponsors_listing_id:,
        transfer_to: nil
      )
        amounts_reversed = currency_corrected_amounts_to_reverse(
          payment_amount_to_reverse: payment_amount_reversed,
          match_amount_to_reverse: match_amount_reversed,
        )
        total_amount_reversed = T.let(amounts_reversed[:payment] + amounts_reversed[:match], Integer)

        metadata = {
          payment_amount_reversed: amounts_reversed[:payment],
          match_amount_reversed: amounts_reversed[:match],
          stripe_refund_id: stripe_refund_id,
          zuora_refund_id: zuora_refund_id,
          sponsors_listing_id: sponsors_listing_id,
        }
        metadata[INTER_ACCOUNT_TRANSFER_KEY] = transfer_to if transfer_to.present?

        begin
          ::Stripe::Transfer.create_reversal(
            stripe_transfer_id,
            amount: total_amount_reversed,
            metadata: metadata,
          )
        rescue ::Stripe::InvalidRequestError => e
          if total_amount_reversed.zero?
            GitHub.logger.info("Sponsors reversal transfer amount is zero.")
            raise TransferReversalAmountIsZero
          elsif e.message =~ /already fully reversed/
            GitHub.logger.info("Transfer already fully reversed.")
            raise TransferAlreadyReversed
          else
            GitHub.logger.info(
              "code.namespace" => "Billing:Stripe:TransferReversal",
              "code.function" => "Stripe::InvalidRequestError when reversing transfer",
              "gh.billing.stripe_transfer.id" => stripe_transfer_id,
              "gh.billing.stripe_transfer.total_amount_reversed" => total_amount_reversed,
              "gh.metadata" => metadata,
            )
            raise
          end
        end

        uncorrected_total = Billing::Money.new(total_cents_from(payment_amount_reversed, match_amount_reversed))
        uncorrected_formatted_total = uncorrected_total.format(no_cents_if_whole: false)
        formatted_total = Billing::Money.new(total_amount_reversed).format(no_cents_if_whole: false)
        message = "#{formatted_total} reversed for Stripe transfer #{stripe_transfer_id}."
        if amounts_reversed[:corrected]
          message += " Currency-corrected from #{uncorrected_formatted_total}."
        end
        if transfer_to.present?
          message += " Will be re-transferred to #{transfer_to}."
        end
        Result.success(message: message)
      end

      sig { params(value1: Types::Numeric, value2: Types::Numeric).returns(Integer) }
      def total_cents_from(value1, value2)
        value1_cents = T.let(value1.is_a?(Money) ? value1.cents : value1, T.any(Integer, Float, BigDecimal))
        value2_cents = T.let(value2.is_a?(Money) ? value2.cents : value2, T.any(Integer, Float, BigDecimal))
        value1_cents.to_i + value2_cents.to_i
      end

      # Private: Given desired amounts to reverse, correct for currency fluctuation if appropriate.
      #
      # The idea here is that if a currency weakens against USD, we can end up reversing more of that currency
      # than we had originally transferred, which is painful for maintainers. Instead, we'll eat the cost
      # of that currency fluctuation.
      #
      # Returns a Hash where the values at the :payment and :match keys are USD cents.
      sig do
        params(
          payment_amount_to_reverse: Types::Numeric,
          match_amount_to_reverse: Types::Numeric,
        ).returns({ payment: Integer, match: Integer, corrected: T::Boolean })
      end
      def currency_corrected_amounts_to_reverse(payment_amount_to_reverse:, match_amount_to_reverse:)
        uncorrected_total_amount_in_cents = total_cents_from(payment_amount_to_reverse, match_amount_to_reverse)
        correction_factor = currency_correction_factor(uncorrected_total_amount_in_cents)

        payment_reversal_amount_in_cents = (payment_amount_to_reverse * correction_factor).to_i
        match_reversal_amount_in_cents = (match_amount_to_reverse * correction_factor).to_i

        {
          payment: payment_reversal_amount_in_cents,
          match: match_reversal_amount_in_cents,
          corrected: correction_factor != 1,
        }
      end

      sig { params(total_reversal_amount_in_cents: Integer).returns(Rational) }
      def currency_correction_factor(total_reversal_amount_in_cents)
        return Rational(1) unless currency_correctable?

        transfer_amount = stripe_transfer.amount
        destination_amount = T.must_because(stripe_transfer.destination_amount) do
          "#currency_correctable? ensures non-nil"
        end
        raw_destination_currency = T.must_because(stripe_transfer.destination_currency) do
          "#currency_correctable? ensures non-nil"
        end
        destination_currency = raw_destination_currency.upcase

        current_destination_amount = Billing::Money.new(transfer_amount).exchange_to(destination_currency).cents
        correction_factor = Rational(destination_amount.cents, current_destination_amount)
          .clamp(Rational(0), Rational(1))

        emit_currency_correction_metrics(total_reversal_amount_in_cents, correction_factor)

        correction_factor
      end

      sig { params(uncorrected_reversal_amount_in_cents: Types::Numeric, correction_factor: Rational).void }
      def emit_currency_correction_metrics(uncorrected_reversal_amount_in_cents, correction_factor)
        datadog_tags = [
          "enabled:true",
        ]
        unrecovered_amount_in_cents = (uncorrected_reversal_amount_in_cents * (1 - correction_factor)).to_i
        datadog_prefix = "sponsors.transfer_reversal.currency_correction"
        GitHub.dogstats.increment("#{datadog_prefix}.count",
          tags: datadog_tags
        )
        GitHub.dogstats.count("#{datadog_prefix}.unrecovered_amount_in_cents", unrecovered_amount_in_cents,
          tags: datadog_tags
        )
      end

      sig { returns T::Boolean }
      def currency_correctable?
        return false if transfer_to.present?

        has_required_fields = [:destination_amount, :destination_currency].all? do |field|
          stripe_transfer.respond_to?(field)
        end
        return false unless has_required_fields

        destination_amount = stripe_transfer.destination_amount
        destination_currency = stripe_transfer.destination_currency
        destination_currency.present? && destination_currency.upcase != "USD" && destination_amount.present?
      end

      sig { returns Transfer }
      memoize def stripe_transfer
        Transfer.from_transfer(::Stripe::Transfer.retrieve(stripe_transfer_id))
      rescue ::Stripe::InvalidRequestError
        raise TransferDoesNotExist
      end

      sig { void }
      def validate_transfer_to!
        if !amount_to_reverse.full_amount?
          raise InvalidRetransfer.new("Must re-transfer full amount.")
        end

        accounts_by_id = StripeConnect::Account.where(
          stripe_account_id: [stripe_transfer.destination, transfer_to]
        ).index_by(&:stripe_account_id)

        origin_account = accounts_by_id[stripe_transfer.destination]
        destination_account = accounts_by_id[transfer_to]
        if origin_account.sponsors_listing_id != destination_account.sponsors_listing_id
          raise InvalidRetransfer.new("Must re-transfer to Stripe account related to the same listing.")
        end
      end
    end
  end
end
