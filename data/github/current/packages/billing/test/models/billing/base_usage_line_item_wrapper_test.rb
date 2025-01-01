# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::BaseUsageLineItemWrapperTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  context "#repository_id" do
    test "returns the repository_id when it is present" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        repository_id: 1,
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::BaseUsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.repository_id, 1)
    end

    test "returns nil when the repository_id is not present (0)" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        repository_id: nil,
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::BaseUsageLineItemWrapper.new(usage_line_item_from_api)
      assert_nil(wrapped_line_item.repository_id)
    end
  end

  context "#multiplier" do
    test "returns the multiplier defined as the product sku plan" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        multiplier: 2,
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::BaseUsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.multiplier, 2)
    end
  end

  context "#actor_id" do
    test "returns the actor_id of the line item" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        actor_id: 2,
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::BaseUsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.actor_id, 2)
    end
  end

  context "#sku_name" do
    test "returns the product sku name of the line item" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "windows",
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::BaseUsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.sku_name, "windows")
    end
  end

  context "#rate_plan_unit_price" do
    test "returns the rate plan unit price of the line item" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        rate_plan_unit_price: 0.08,
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::BaseUsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.rate_plan_unit_price, 0.08)
    end
  end

  context "#to_hash" do
    test "properly hashes the BaseUsageLineItemWrapper object" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        quantity: 1,
        custom_fields: {
          "random.custom.id" => "12345",
        }
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::BaseUsageLineItemWrapper.new(usage_line_item_from_api)
      line_item_hashed = wrapped_line_item.to_hash
      line_item = line_item_hashed[:usage_line_item]
      assert_equal(line_item[:custom_fields], { "random.custom.id" => "12345" })
      assert_equal(line_item[:quantity], 1.0)
    end
  end
end
