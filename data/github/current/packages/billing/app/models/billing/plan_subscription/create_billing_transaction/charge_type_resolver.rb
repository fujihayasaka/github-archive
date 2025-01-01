# typed: strict
# frozen_string_literal: true


# TODO: This class relies too much on the charge name
# Instead we should use the product UUIDs product rate plan charge and the invoice items
# product rate plan charge for any matching.
module Billing
  # A helper class to find what type of charge a zuora transaction is for
  # Ex `prorate-charge`, `prorate-seat-charge`, `prorate-asset-pack-charge`
  class PlanSubscription::CreateBillingTransaction::ChargeTypeResolver
    extend T::Sig

    include GitHub::Memoizer

    delegate :invoice_items, to: :payment

    sig { params(payment: T.any(Billing::Zuora::Payment, Billing::Zuora::CreditBalanceAdjustment), recurring_amount: Billing::Types::Numeric).void }
    def initialize(payment:, recurring_amount:)
      @payment = payment
      @recurring_amount = recurring_amount
    end

    sig { returns(Integer) }
    def seats_delta
      return 0 unless prorated? && seats_upgrade? && !duration_change?

      previous_items = per_seat_invoice_item_groups.values.flatten.select { |item| item.charge_amount.negative? }
      new_items = per_seat_invoice_item_groups.values.flatten.select { |item| item.charge_amount.positive? }

      get_delta(previous_items, new_items)
    end

    # Public: The number of added or removed data packs
    sig { returns(Integer) }
    def asset_packs_delta
      return 0 unless prorated? && data_pack_upgrade? && !duration_change?

      previous_items = invoice_items.select { |item| item.charge_amount.negative? }
      new_items = invoice_items.select { |item| item.charge_amount.positive? }

      get_delta(previous_items, new_items)
    end

    sig { returns(T.nilable(String)) }
    def charge_type
      if prorated? && seats_delta > 0
        "prorate-seat-charge"
      elsif prorated? && asset_packs_delta > 0
        "prorate-asset-pack-charge"
      elsif prorated?
        "prorate-charge"
      end
    end

    sig { returns(T::Boolean) }
    def data_pack_upgrade?
      return false unless invoice_items.present? && prorated?
      invoice_items.first.charge_name.include?(Asset::Status.zuora_product_name)
    end

    sig { returns(T::Boolean) }
    def seats_upgrade?
      return false if per_seat_invoice_item_groups.length > 1 || !prorated?
      per_seat_invoice_item_groups.any? do |_charge_name, items|
        (items.count > 1) && # Switching between seat plans includes a single item without credit
        items.any? { |item| item.unit == "Seats" && item.quantity > 0 }
      end
    end

    private

    sig { returns(T.any(Billing::Zuora::Payment, Billing::Zuora::CreditBalanceAdjustment)) }
    attr_reader :payment

    sig { returns(Billing::Types::Numeric) }
    attr_reader :recurring_amount

    sig { returns(T::Boolean) }
    memoize def prorated?
      (recurring_amount != payment.amount) && !usage?
    end
    # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

    sig { returns(T::Boolean) }
    def usage?
      invoice_items.any? do |item|
        BillingTransaction::LineItem::USAGE_DESCRIPTIONS.include?(item.charge_name) && item.quantity > 0
      end
    end

    # Private: Per seat charges grouped by type
    #
    # Returns one group consisting of pairs of seat charge, in each pair one of which is the credit or $0
    # charge for the previous amount of seats and the other is the new charge for the added
    # seats.
    #
    # Ex:
    # {"GitHub Business Plan - Month"=> # [
    #   #<Billing::Zuora::InvoiceItem:0x0000000117fb7f58
    #     @invoice_item_response=
    #       {
    #         "ChargeAmount"=>-121.8,
    #         "Id"=>"2c92c0fa65f203fe0165f74569e728ab",
    #         "Quantity"=>6,
    #         "UOM"=>"Seats",
    #         "ChargeName"=>"GitHub Business Plan - Month"
    #       }>,
    #   #<Billing::Zuora::InvoiceItem:0x0000000117fb7e18
    #     @invoice_item_response=
    #       {
    #         "ChargeAmount"=>162.4,
    #         "Id"=>"2c92c0fa65f203fe0165f74569e828ac",
    #         "Quantity"=>8,
    #         "UOM"=>"Seats",
    #         "ChargeName"=>"GitHub Business Plan - Month"
    #       }>
    # ]}
    sig { returns(T::Hash[String, T::Array[Billing::Zuora::InvoiceItem]]) }
    def per_seat_invoice_item_groups
      invoice_charge_groups.select do |charge_name, _items|
        per_seat_charge_names.any? { |name| charge_name.include?(name) }
      end
    end

    # Private: Invoice Items grouped by their charge name
    sig { returns(T::Hash[String, T::Array[Billing::Zuora::InvoiceItem]]) }
    def invoice_charge_groups
      invoice_items.group_by(&:charge_name)
    end

    sig { returns(T::Array[String]) }
    def per_seat_charge_names
      # This plan name was changed in Zuora by financial systems to "GitHub Enterprise Cloud"
      # but we still need to support the old name in case there's subscriptions that still have
      # the old name
      legacy_enterprise_cloud_plan_name = ["GitHub Business Cloud"]
      GitHub::Plan.per_seat_plans.map(&:zuora_product_name) + legacy_enterprise_cloud_plan_name
    end

    sig { returns(T::Boolean) }
    def duration_change?
      invoice_items.any? { |item| item.charge_name.include?("Year") } &&
        invoice_items.any? { |item| item.charge_name.include?("Month") }
    end

    # Private: Gets the delta between previous and new items
    sig do
      params(previous_items: T::Array[Billing::Zuora::InvoiceItem], new_items: T::Array[Billing::Zuora::InvoiceItem])
        .returns(Integer)
    end
    def get_delta(previous_items, new_items)
      if previous_items.length > 0
        new_items.sum(&:quantity) - previous_items.sum(&:quantity)
      else
        new_items.sum(&:quantity)
      end.to_i
    end
  end
end
