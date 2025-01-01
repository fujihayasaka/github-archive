# typed: strict
# frozen_string_literal: true

module Billing
  module Stripe
    class TransferPayments
      extend T::Sig

      include GitHub::Memoizer

      InvalidChargeId = Class.new(StandardError)
      DEFAULT_CURRENCY = "usd"

      # Public: Transfer payments to their maintainers Stripe Connect accounts
      sig { params(sponsors_line_items: T::Array[::Billing::BillingTransaction::LineItem], zuora_payment: ::Billing::Zuora::Payment).void }
      def self.perform(sponsors_line_items, zuora_payment)
        new(sponsors_line_items, zuora_payment).perform
      end

      # Public: Initialize a new TransferPayment object
      sig { params(sponsors_line_items: T::Array[::Billing::BillingTransaction::LineItem], zuora_payment: ::Billing::Zuora::Payment).void }
      def initialize(sponsors_line_items, zuora_payment)
        @sponsors_line_items = sponsors_line_items
        @zuora_payment = zuora_payment
      end

      # Public: Transfer payments to their maintainers Stripe Connect accounts
      sig { void }
      def perform
        return if sponsors_line_items_with_match_excluding_fees.empty?

        # There may be multiple line items for different tiers on the same listing - eg.
        # when a sponsor does a midcycle upgrade there will be two line items:
        # - a prorated credit on the old tier
        # - a prorated charge on the new tier
        #
        # We need to combine line items and transfer the net amount to properly reflect
        # what the sponsor was charged.
        grouped_line_items = sponsors_line_items_with_match_excluding_fees.group_by(&:sponsors_listing_id)

        grouped_line_items.each do |_, sponsors_line_items|
          net_total = sponsors_line_items.sum(&:total_in_cents)
          create_stripe_transfer(sponsors_line_items) if net_total > 0
        end
      end

      private

      sig { returns(::Billing::Zuora::Payment) }
      attr_reader :zuora_payment

      sig { returns(T::Array[::Billing::BillingTransaction::LineItem]) }
      attr_reader :sponsors_line_items

      sig { params(sponsors_line_items: T::Array[::Billing::Sponsors::LineItemWithMatch]).returns(T.nilable(::Stripe::Transfer)) }
      def create_stripe_transfer(sponsors_line_items)
        # Get amounts from all the line items:
        amount_in_cents = sponsors_line_items.sum(&:amount_in_cents)
        match_amount_in_cents = sponsors_line_items.sum(&:match_amount_in_cents)
        total_in_cents = sponsors_line_items.sum(&:total_in_cents)

        # Get non-monetary data from any of the line items:
        sponsors_line_item = sponsors_line_items.first
        stripe_account_id = T.unsafe(sponsors_line_item).sponsors_stripe_transfer_account_id
        listing_id = T.unsafe(sponsors_line_item).sponsors_listing_id

        metadata = {
          payment_amount: amount_in_cents,
          match_amount: match_amount_in_cents,
          stripe_charge_id: nil,
          sponsors_listing_id: listing_id,
        }.merge(zuora_payment.sponsors_metadata)

        ::Stripe::Transfer.create(
          amount: total_in_cents,
          currency: DEFAULT_CURRENCY,
          destination: stripe_account_id,
          transfer_group: transfer_group,
          metadata: metadata,
        )
      rescue ::Stripe::InvalidRequestError => e
        GitHub.dogstats.increment("stripe.transfer.failed")
        Failbot.report(e)
        T.unsafe(sponsors_line_item).instrument_transfer_failure(billing_line_items: sponsors_line_items, reason: e.message)

        nil
      rescue ::Stripe::PermissionError => e
        GitHub.dogstats.increment("stripe.permission_error", tags: ["action:transfer"])
        Failbot.report(e)
        T.unsafe(sponsors_line_item).instrument_transfer_failure(billing_line_items: sponsors_line_items, reason: e.message)

        nil
      rescue => e # rubocop:todo Lint/GenericRescue
        # record error and re-raise exception
        T.unsafe(sponsors_line_item).instrument_transfer_failure(billing_line_items: sponsors_line_items, reason: e.message)
        raise
      end

      sig { returns(String) }
      def transfer_group
        zuora_payment.id
      end

      sig { returns(T::Array[::Billing::Sponsors::LineItemWithMatch]) }
      memoize def sponsors_line_items_with_match_excluding_fees
        filtered_line_items = sponsors_line_items.select do |line_item|
          !line_item.sponsors_fee? && line_item.sponsors_stripe_transfer_account_id.present?
        end
        filtered_line_items.map { |line_item| Billing::Sponsors::LineItemWithMatch.new(line_item) }
      end
    end
  end
end
