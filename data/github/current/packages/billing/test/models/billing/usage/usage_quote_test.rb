# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Usage::UsageQuoteTest < GitHub::TestCase
  context "#product_name" do
    test "returns a string product name" do
      usage_quote = build(:usage_quote)

      assert_equal usage_quote.product_name, "actions"
    end
  end

  context "#product_sku_name" do
    test "returns a string product sku" do
      usage_quote = build(:usage_quote)

      assert_equal usage_quote.product_sku_name, "linux"
    end
  end

  context "#proposed_estimated_cost" do
    test "returns an integer estimated cost" do
      usage_quote = build(:usage_quote)

      assert_equal usage_quote.proposed_estimated_cost, 80
    end
  end

  context "#proposed_quantity" do
    test "returns an integer proposed_quantity" do
      usage_quote = build(:usage_quote)

      assert_equal usage_quote.proposed_quantity, 100
    end
  end

  context "#proposed_effective_quantity" do
    test "returns an integer proposed_effective_quantity" do
      usage_quote = build(:usage_quote)

      assert_equal usage_quote.proposed_effective_quantity, 100
    end
  end

  context "#proposed_billable_quantity" do
    test "returns an integer proposed_billable_quantity" do
      usage_quote = build(:usage_quote)

      assert_equal usage_quote.proposed_billable_quantity, 100
    end
  end

  context "#actions_linux?" do
    test "returns true when product_name is 'actions' and product_sku_name is 'linux'" do
      usage_quote = build(:usage_quote)
      assert usage_quote.actions_linux?
    end

    test "returns false when product_name and product_sku_name don't match'" do
      usage_quote = build(:usage_quote, product_sku_name: "linux_12_core")
      refute usage_quote.actions_linux?
    end
  end

  context "#packages?" do
    test "returns true when product_name is 'packages' and product_sku_name is 'default'" do
      usage_quote = build(:usage_quote, product_name: "packages", product_sku_name: "default")
      assert usage_quote.packages?
    end

    test "returns false when product_name and product_sku_name don't match" do
      usage_quote = build(:usage_quote, product_name: "packages", product_sku_name: "test")
      refute usage_quote.packages?
    end
  end

  context "#shared_storage?" do
    test "returns true when product_name is 'shared_storage' and product_sku_name is 'default'" do
      usage_quote = build(:usage_quote, product_name: "shared_storage", product_sku_name: "default")
      assert usage_quote.shared_storage?
    end

    test "returns false when product_name and product_sku_name don't match" do
      usage_quote = build(:usage_quote, product_name: "shared_storage", product_sku_name: "test")
      refute usage_quote.shared_storage?
    end
  end
end
