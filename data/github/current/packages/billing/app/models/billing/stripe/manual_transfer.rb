# typed: strict
# frozen_string_literal: true

module Billing
  module Stripe
    # Public: Allows transferring money to a Stripe Connect account by creating a Stripe::Transfer object.
    class ManualTransfer
      class TotalTransferAmountError < StandardError; end

      DEFAULT_CURRENCY = "usd"
      MUST_HAVE_STRIPE_ACCOUNT_ID_ERROR_MESSAGE = "Must have a Stripe Connect account id."
      MUST_HAVE_SPONSOR_LISTING_ID_ERROR_MESSAGE = "Must have a sponsors listing id."
      TOTAL_TRANSFER_AMOUNT_ERROR_MESSAGE = "Cannot transfer a negative amount of money."

      class Result
        sig { returns(T.nilable(String)) }
        attr_reader :transfer_id

        sig { returns(T.nilable(String)) }
        attr_reader :message

        sig { returns(T::Boolean) }
        attr_reader :success
        alias_method :success?, :success

        # success – a Boolean indicating the success of an operation.
        # errors – an Array of String error messages.
        # transfer_id - optional String ID of the Stripe::Transfer that gets created
        sig { params(success: T::Boolean, message: T.nilable(String), transfer_id: T.nilable(String)).void }
        def initialize(success:, message:, transfer_id: nil)
          @transfer_id = transfer_id
          @success     = success
          @message     = message
        end

        sig { params(transfer_id: String, message: T.nilable(String)).returns(Result) }
        def self.success(transfer_id:, message: nil)
          new(transfer_id: transfer_id, success: true, message: message)
        end

        sig { params(error: String).returns(Result) }
        def self.failure(error:)
          new(success: false, message: error)
        end
      end

      # Public: Create a manual transfer to a Stripe Connect account
      sig do
        params(
          stripe_account_id:  T.nilable(String),
          sponsors_listing_id: T.nilable(Integer),
          payment_amount: Integer,
          match_amount: Integer,
          currency: T.nilable(String),
          transfer_group: T.nilable(String),
          stripe_charge_id: T.nilable(String),
        ).returns(Result)
      end
      def self.perform(stripe_account_id:, sponsors_listing_id:, payment_amount: 0, match_amount: 0, currency: nil, transfer_group: nil, stripe_charge_id: nil)
        new(
          stripe_account_id: stripe_account_id,
          sponsors_listing_id: sponsors_listing_id,
          payment_amount: payment_amount,
          match_amount: match_amount,
          currency: currency,
          transfer_group: transfer_group,
          stripe_charge_id: stripe_charge_id
        ).perform
      end

      # Public: Initialize a new ManualTransfer object
      #
      # stripe_account_id         - A String representing the Stripe Connect account id, e.g., "acct_1Ep35IFxJZYbadPl"
      # payment_amount            - The amount in cents of the cardholder's payment
      # match_amount              - The amount in cents of the GitHub match
      # currency                  - Three-character currency code of the amount you're transferring
      # transfer_group            - A String representing the initial platform_transaction_id from the
      #                             transaction that triggered the transfer (optional), e.g., "e.g., re_1HtI7VEQsq43iHhXcEjdABCD"
      # stripe_charge_id          - A String representing the stripe charge id (optional), e.g., "2c92a0ff732347120173280442a123a3"
      # sponsors_listing_id       - Integer SponsorsListing ID
      sig do
        params(
          stripe_account_id:  T.nilable(String),
          sponsors_listing_id: T.nilable(Integer),
          payment_amount: Integer,
          match_amount: Integer,
          currency: T.nilable(String),
          transfer_group: T.nilable(String),
          stripe_charge_id: T.nilable(String),
        ).void
      end
      def initialize(stripe_account_id:, sponsors_listing_id:, payment_amount: 0, match_amount: 0, currency: nil, transfer_group: nil, stripe_charge_id: nil)
        @stripe_account_id    = stripe_account_id
        @payment_amount       = payment_amount
        @match_amount         = match_amount
        # Note that the three-letter ISO code is provided for each currency below, but you should provide
        # the ISO code in all lowercase letters when making the charge request
        # See more https://stripe.com/docs/currencies#presentment-currencies
        @currency             = T.let(currency&.downcase || DEFAULT_CURRENCY, String)
        @transfer_group       = transfer_group
        @stripe_charge_id     = stripe_charge_id
        @sponsors_listing_id  = sponsors_listing_id
      end

      # Public: Create manual transfer to maintainer's Stripe Connect account.
      sig { returns(Result) }
      def perform
        return Result.failure(error: MUST_HAVE_STRIPE_ACCOUNT_ID_ERROR_MESSAGE) unless stripe_account_id
        return Result.failure(error: MUST_HAVE_SPONSOR_LISTING_ID_ERROR_MESSAGE) unless sponsors_listing_id
        return Result.failure(error: TOTAL_TRANSFER_AMOUNT_ERROR_MESSAGE) if total_transfer_amount <= 0

        create_manual_transfer
      rescue ::Stripe::InvalidRequestError => e
        GitHub.dogstats.increment("stripe.transfer.failed")
        Failbot.report(e)
        Result.failure(error: e.message.to_s)
      rescue ::Stripe::PermissionError => e
        GitHub.dogstats.increment("stripe.permission_error", tags: ["action:transfer"])
        Failbot.report(e)
        Result.failure(error:  e.message.to_s)
      end

      private

      sig { returns(T.nilable(String)) }
      attr_reader :stripe_account_id

      sig { returns(Integer) }
      attr_reader :payment_amount

      sig { returns(Integer) }
      attr_reader :match_amount

      sig { returns(String) }
      attr_reader :currency

      sig { returns(T.nilable(String)) }
      attr_reader :transfer_group

      sig { returns(T.nilable(String)) }
      attr_reader :stripe_charge_id

      sig { returns(T.nilable(Integer)) }
      attr_reader :sponsors_listing_id

      sig { returns(Result) }
      def create_manual_transfer
        transfer = ::Stripe::Transfer.create(
          amount: total_transfer_amount,
          currency: currency,
          destination: stripe_account_id,
          transfer_group: transfer_group,
          metadata: {
            payment_amount: payment_amount,
            match_amount: match_amount,
            stripe_charge_id: stripe_charge_id,
            sponsors_listing_id: sponsors_listing_id,
          },
        )

        formatted_total = Billing::Money.new(total_transfer_amount, currency).format(no_cents_if_whole: false)
        Result.success(transfer_id: transfer.id, message: "#{formatted_total} manual transfer created. Stripe Transfer ID: #{transfer.id}")
      end

      sig { returns(Integer) }
      def total_transfer_amount
        @total_transfer_amount ||= T.let(payment_amount + match_amount, T.nilable(Integer))
      end
    end
  end
end
