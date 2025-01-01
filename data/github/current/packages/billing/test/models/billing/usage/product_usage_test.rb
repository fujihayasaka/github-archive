# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Usage::ProductUsageTest < GitHub::TestCase
  context "#product_name" do
    test "returns a string product name" do
      product_usage = build(:billing_product_usage)

      assert_equal product_usage.product_name, "actions"
    end
  end

  context "#product_sku_name" do
    test "returns a string product sku" do
      product_usage = build(:billing_product_usage)

      assert_equal product_usage.product_sku_name, "linux"
    end
  end

  context "#unit_of_measure" do
    test "returns a string unit of measure" do
      product_usage = build(:billing_product_usage)

      assert_equal product_usage.unit_of_measure, "Minutes"
    end
  end

  context "#estimated_cost" do
    test "returns an integer estimated cost" do
      product_usage = build(:billing_product_usage)

      assert_equal product_usage.estimated_cost, 80
    end
  end

  context "#quantity" do
    test "returns an integer quantity" do
      product_usage = build(:billing_product_usage)

      assert_equal product_usage.quantity, 100
    end
  end

  context "#effective_quantity" do
    test "returns an integer effective_quantity" do
      product_usage = build(:billing_product_usage)

      assert_equal product_usage.effective_quantity, 100
    end
  end

  context "#billable_quantity" do
    test "returns an integer billable_quantity" do
      product_usage = build(:billing_product_usage)

      assert_equal product_usage.billable_quantity, 100
    end
  end
end
