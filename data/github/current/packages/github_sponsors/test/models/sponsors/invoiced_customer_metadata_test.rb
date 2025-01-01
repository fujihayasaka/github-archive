# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsInvoicedCustomerMetadataTest < GitHub::TestCase
  JANUARY = Time.parse("2022-01-01")
  MARCH = Time.parse("2022-03-01")
  APRIL = Time.parse("2022-04-01")

  fixtures do
    @one_time_tier = create(:sponsors_tier, :one_time)
    @recurring_tier = create(:sponsors_tier, :recurring)
    @one_time_item = create(:billing_transaction_line_item, amount_in_cents: 100_00, subscribable: @one_time_tier, created_at: JANUARY)
    @recurring_item = create(:billing_transaction_line_item, amount_in_cents: 100_00, subscribable: @recurring_tier, created_at: JANUARY)
  end

  context "#monthly_payments_in_dollars" do
    test "includes information about one time payments" do
      metadata = Sponsors::InvoicedCustomerMetadata.new(line_items: [@one_time_item, @recurring_item])
      expected_item = ["Jan", 100, "one-time"]

      result = metadata.monthly_payments_in_dollars

      assert_includes result, expected_item
    end

    test "includes information about recurring payments" do
      metadata = Sponsors::InvoicedCustomerMetadata.new(line_items: [@one_time_item, @recurring_item])
      expected_item = ["Jan", 100, "recurring"]

      result = metadata.monthly_payments_in_dollars

      assert_includes result, expected_item
    end

    test "combines totals with the same month and frequency" do
      extra_recurring = create(:billing_transaction_line_item, amount_in_cents: 100_00, subscribable: @recurring_tier, created_at: JANUARY)
      metadata = Sponsors::InvoicedCustomerMetadata.new(line_items: [@one_time_item, @recurring_item, extra_recurring])
      expected_item = ["Jan", 200, "recurring"]

      result = metadata.monthly_payments_in_dollars

      assert_includes result, expected_item

    end

    test "includes months that do not have data" do
      metadata = Sponsors::InvoicedCustomerMetadata.new(line_items: [])
      expected_item = ["Jan", 0, "recurring"]

      result = metadata.monthly_payments_in_dollars

      assert_equal 24, result.length
      assert_includes result, expected_item
    end
  end

  context "#aggregate_yearly_payments_in_dollars" do
    test "returns the total value of all line items for the year" do
      metadata = Sponsors::InvoicedCustomerMetadata.new(line_items: [@one_time_item, @recurring_item])

      result = metadata.aggregate_yearly_payments_in_dollars

      assert_equal 200, result
    end

    test "returns zero if there are no line items" do
      metadata = Sponsors::InvoicedCustomerMetadata.new(line_items: [])

      result = metadata.aggregate_yearly_payments_in_dollars

      assert_equal 0, result
    end
  end

  context "#aggregate_monthly_payments_in_dollars" do
    test "calcuates payment amounts for months with line items" do
      metadata = Sponsors::InvoicedCustomerMetadata.new(line_items: [@one_time_item, @recurring_item])
      expected_item = { month: "Jan", recurring: 100, one_time: 100, total: 200 }

      result = metadata.aggregate_monthly_payments_in_dollars

      assert_includes result, expected_item
    end

    test "includes zero values for months without line items" do
      metadata = Sponsors::InvoicedCustomerMetadata.new(line_items: [@one_time_item, @recurring_item])
      expected_item = { month: "Feb", recurring: 0, one_time: 0, total: 0 }

      result = metadata.aggregate_monthly_payments_in_dollars

      assert_includes result, expected_item
    end
  end
end
