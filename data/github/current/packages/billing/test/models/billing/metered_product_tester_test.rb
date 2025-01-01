# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::MeteredProductTesterTest < GitHub::TestCase
  include HydroTestHelpers
  include ::Billing::ApiTestHelpers

  context "#emit_test_usage" do
    test "emits test usage without customer" do
      product_name = "Wall-E Trash Compactor"
      product_sku_name = "EzPz"
      quantity = 1.0
      user = create(:user)
      tester = Billing::MeteredProductTester.new(
        product_name: product_name,
        product_sku_name: product_sku_name,
        quantity: quantity,
        source: "User_#{user.id}",
        user: user
      )
      assert_equal false, tester.usage_emitted?
      tester.emit_test_usage
      assert_equal true, tester.usage_emitted?
      assert_hydro_published_partial({
        product_name: product_name,
        product_sku_name: product_sku_name,
        account_id: user.id,
        customer_id: nil,
        actor_id: user.id,
        quantity: quantity,
        source_uri: "gid://stafftools_test",
      }, schema: "meuse.v0.MeteredUsage")
    end

    test "emits test usage with a non-user source without customer" do
      product_name = "Wall-E Trash Compactor"
      product_sku_name = "EzPz"
      quantity = 1.0
      user = create(:user)
      org = create(:organization)
      tester = Billing::MeteredProductTester.new(
        product_name: product_name,
        product_sku_name: product_sku_name,
        quantity: quantity,
        source: "Org_#{org.id}",
        user: user
      )
      assert_equal false, tester.usage_emitted?
      tester.emit_test_usage
      assert_equal true, tester.usage_emitted?
      assert_hydro_published_partial({
        product_name: product_name,
        product_sku_name: product_sku_name,
        account_id: org.id,
        customer_id: nil,
        actor_id: user.id,
        quantity: quantity,
        source_uri: "gid://stafftools_test",
      }, schema: "meuse.v0.MeteredUsage")
    end

    test "does not emit test usage if required params are missing" do
      product_name = "Ratatouille Cooking Set"
      product_sku_name = nil
      quantity = 1.0
      user = create(:user)
      tester = Billing::MeteredProductTester.new(
        product_name: product_name,
        product_sku_name: product_sku_name,
        quantity: quantity,
        source: "User_#{user.id}",
        user: user
      )
      assert_equal false, tester.usage_emitted?
      tester.emit_test_usage
      assert_equal false, tester.usage_emitted?
      refute_hydro_messages(schema: "meuse.v0.MeteredUsage")
    end

    test "emits customer id if customer exists" do
      product_name = "Wall-E Trash Compactor"
      product_sku_name = "EzPz"
      quantity = 1.0
      user = create(:user)
      business = create(:business)
      tester = Billing::MeteredProductTester.new(
        product_name: product_name,
        product_sku_name: product_sku_name,
        quantity: quantity,
        source: "Enterprise_#{business.id}",
        user: user
      )
      assert_equal false, tester.usage_emitted?
      tester.emit_test_usage
      assert_equal true, tester.usage_emitted?
      assert_hydro_published_partial({
        product_name: product_name,
        product_sku_name: product_sku_name,
        account_id: nil,
        customer_id: business.customer.id,
        actor_id: user.id,
        quantity: quantity,
        source_uri: "gid://stafftools_test",
      }, schema: "meuse.v0.MeteredUsage")
    end
  end

  context "calculate_test_usage" do
    test "calculates test usage correctly" do
      user = create(:user)
      product_name = "codespaces"
      product_sku_name = "compute_d4"
      tester = Billing::MeteredProductTester.new(
        product_name: product_name,
        product_sku_name: product_sku_name,
        quantity: 1.0,
        source: "User_#{user.id}",
        user: user
      )

      mock_get_usage_breakdown(
        products: create_product_breakdown_array(
          name: product_name,
          skus: [create_skus_breakdown_hash(sku: product_sku_name)]
        )
      )
      usage_breakdown = tester.calculate_test_usage
      assert usage_breakdown.is_a?(Billing::UsageChecker::UsageResult), "usage_breakdown is not a Billing::UsageChecker::UsageResult"
    end

    test "does not calculate usage breakdown if required params are missing" do
      user = create(:user)
      product_name = "codespaces"
      product_sku_name = nil
      tester = Billing::MeteredProductTester.new(
        product_name: product_name,
        product_sku_name: product_sku_name,
        quantity: 1.0,
        source: "User_#{user.id}",
        user: user
      )
      assert_nil tester.calculate_test_usage
    end

    test "provides error details" do
      user = create(:user)
      product_name = "codespaces"
      product_sku_name = "compute_d4"
      tester = Billing::MeteredProductTester.new(
        product_name: product_name,
        product_sku_name: product_sku_name,
        quantity: 1.0,
        source: "User_#{user.id}",
        user: user
      )
      mock_get_usage_breakdown_response_error
      usage_breakdown = tester.calculate_test_usage
      assert usage_breakdown.nil?, "usage_breakdown should be nil when there is an error"
      assert_match "Error getting usage breakdown.", tester.error_message
    end
  end
end
