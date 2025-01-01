# typed: strict
# frozen_string_literal: true

module Billing
  module Zuora
    # Creates invoice item adjustments items that can be sent to Zuora to adjust an invoice balance.
    # Intended to be used for zeroing out invoices as the adjustments do not take into account what
    # the invoice items are for.
    #
    # Notes:
    #  * Invoice amount is not the same as the invoice balance; invoice amount does not include adjustments, but invoice balance does.
    #  * The adjustments are applied by Zuora in the same order they are provided in.
    #  * Adjustments that cause an invoice balance to go from positive to negative (or vice-versa) will fail.
    #  * Adjustments that cause a positive invoice balance to go outside the range of [0, Invoice Amount] will fail.
    #  * Adjustments that cause a negative invoice balance to go outside the range of [Invoice Amount, 0] will fail.
    class InvoiceItemAdjustmentBuilder
      extend T::Sig

      # Public: Get data for a Zuora API call to create an invoice item adjustment.
      #
      # amount - amount for the adjustment
      # invoice_id - ID of the Zuora invoice with the item to adjust
      # item_id - ID of the Zuora invoice item to adjust
      sig do
        params(
          amount: Billing::Types::Numeric,
          invoice_id: String,
          item_id: String,
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def self.adjustment_for(amount:, invoice_id:, item_id:)
        # See https://www.zuora.com/developer/api-references/older-api/operation/Object_POSTInvoiceItemAdjustment/
        {
          AdjustmentDate: GitHub::Billing.today.to_s,
          Amount: amount.abs,
          InvoiceId: invoice_id,
          SourceId: item_id,
          SourceType: "InvoiceDetail",
          Type: amount.positive? ? "Charge" : "Credit",
        }
      end

      # Public: Increment a count in DataDog with details about invoice item adjustments.
      #
      # adjustments - an Array of Hash invoice item adjustments
      # class_tag - String to use as a DataDog tag describing which class is creating invoice item adjustments
      # product - optional String like "copilot" or "sponsors" to describe what GitHub product the invoice items
      #           being adjusted are from
      #
      sig do
        params(
          adjustments: T::Array[T::Hash[Symbol, T.untyped]],
          class_tag: String,
          product: T.nilable(String),
        ).void
      end
      def self.instrument_invoice_item_adjustments(adjustments, class_tag:, product: nil)
        return if adjustments.empty?

        amount_in_dollars = adjustments.sum { |a| a.fetch(:Amount, 0) }

        GitHub.dogstats.count(
          "zuora.invoices.zero_out_line_items.amount_in_cents",
          amount_in_dollars * 100,
          tags: ["class:#{class_tag}", "product:#{product}"],
        )
      end

      # Public: Returns an array of adjustments that can be sent to Zuora to adjust an invoice balance.
      sig do
        params(
          invoice: Billing::Zuora::Invoice,
          adjustment_amount: Billing::Money,
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def self.perform(invoice:, adjustment_amount:)
        # Do nothing if the adjustment amount is zero
        return [] if invoice.amount.zero? || adjustment_amount.zero?

        # Check that we can actually adjust the invoice by the adjustment amount
        valid_balance_range = invoice.amount.positive? ? (0..invoice.amount) : (invoice.amount..0)
        desired_balance = invoice.balance + adjustment_amount.to_f
        unless valid_balance_range.include?(desired_balance)
          Failbot.report(
            ArgumentError.new("Invalid invoice adjustment amount"),
            {
              "gh.billing.zuora.invoice.id" => invoice.id,
              "gh.billing.zuora.invoice_adjustment.amount" => adjustment_amount
            }
          )
          return []
        end

        items_to_zero_out = invoice.invoice_items

        # Get the current invoice items and sort them in descending order by their charge amount
        # This allows us to create the least amount of adjustments possible.
        sorted_invoice_items = if invoice.amount.positive?
          items_to_zero_out.sort_by { |item| -item.charge_amount }
        else
          items_to_zero_out.sort_by(&:charge_amount)
        end

        # Create adjustments until we have zeroed out the adjustment amount
        adjustments = []
        sorted_invoice_items.each do |item|
          # Check how much we can adjust this item; skip if we can't adjust it
          max_item_adjustment = item.charge_amount
          next if max_item_adjustment.zero?

          # Create the adjustment for this item
          item_adjustment_amount = if adjustment_amount.abs > max_item_adjustment.abs
            -max_item_adjustment
          else
            adjustment_amount
          end

          adjustments << adjustment_for(amount: item_adjustment_amount, invoice_id: invoice.id, item_id: item.id)

          # Update our adjustment amount and check if we are done
          adjustment_amount = T.cast(adjustment_amount - item_adjustment_amount, Billing::Money)
          break if adjustment_amount.zero?
        end

        # Check that we were able to actually adjust the invoice by the adjustment amount
        unless adjustment_amount.zero?
          Failbot.report(
            StandardError.new("Could not adjust invoice by the provided adjustment amount"),
            {
              "gh.billing.zuora.invoice.id" => invoice.id,
              "gh.billing.zuora.invoice_adjustment.amount" => adjustment_amount,
            }
          )
        end

        adjustments
      end
    end
  end
end
