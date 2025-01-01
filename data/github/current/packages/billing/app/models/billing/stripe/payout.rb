# typed: true
# frozen_string_literal: true

module Billing
  module Stripe
    # Class used to wrap Stripe::Payout
    # Allows us to override Payout#amount for cases where Stripe & RubyMoney disagree
    class Payout

      # Special case for currencies where Stripe and RubyMoney disagree on subunits
      SUBUNIT_OVERRIDES_BY_CURRENCY_CODE = {
        # see https://stripe.com/docs/currencies?presentment-currency=HU#special-cases
        # see https://github.com/RubyMoney/money/issues/677
        huf: 100
      }.freeze

      sig { params(stripe_payout: ::Stripe::Payout, stripe_account_id: String).void }
      def initialize(stripe_payout:, stripe_account_id:)
        @stripe_payout = stripe_payout
        @stripe_account_id = stripe_account_id
      end

      sig { returns ::Stripe::Payout }
      attr_reader :stripe_payout

      sig { returns String }
      attr_reader :stripe_account_id

      delegate :id, :arrival_date, :created, :currency, :destination, :statement_descriptor, :status,
        :failure_code, to: :stripe_payout

      sig { returns Integer }
      def amount
        result = Billing::Stripe::Payout.special_case_subunit(stripe_payout.amount, currency)
        T.cast(result, Integer)
      end

      sig { returns Billing::Money }
      def to_money
        Billing::Money.new(amount, currency)
      end

      sig { returns Time }
      def created_at
        Time.at(created)
      end

      # Public: Special case subunit to unit conversion for currencies where Stripe and RubyMoney disagree
      # see https://github.com/github/sponsors/issues/4720
      #
      # amount - in subunits (eg 100 to represent $1 usd)
      # currency - three-letter currency code (eg "usd")
      #
      # Returns Integer or Billing::Money, whichever type was passed in for `amount`.
      sig do
        params(
          amount: T.any(Billing::Money, Integer),
          currency: T.any(String, Symbol)
        ).returns(T.any(Billing::Money, Integer))
      end
      def self.special_case_subunit(amount, currency)
        subunit_override = SUBUNIT_OVERRIDES_BY_CURRENCY_CODE[currency.to_sym]
        return amount / subunit_override if subunit_override.present?

        amount
      end
    end
  end
end
