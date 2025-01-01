# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Codespaces::UsageLineItemWrapperTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  context "#end_time" do
    test "returns the end_time when it is present" do
      usage_at = (GitHub::Billing.today - 1.day).to_time
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i)
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Codespaces::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.end_time, usage_at)
    end
  end

  context "#usage" do
    test "returns the usage when quantity is present" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        quantity: 5.0
      ).data.usage_line_items[0]
      wrapped_line_item = Billing::Codespaces::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.usage, 5.0)
    end
  end

  context "#unit_type" do
    test "returns the unit_type when it the product sku name is 'storage'" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "storage"
      ).data.usage_line_items[0]
      wrapped_line_item = Billing::Codespaces::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.unit_type, "gb-month")
    end

    test "returns the unit_type when it the product sku name is 'prebuilds_storage'" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "prebuild_storage"
      ).data.usage_line_items[0]
      wrapped_line_item = Billing::Codespaces::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.unit_type, "gb-month")
    end

    test "returns the unit_type when it the product sku name is not 'storage' or 'prebuilds_storage'" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "not storage"
      ).data.usage_line_items[0]
      wrapped_line_item = Billing::Codespaces::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.unit_type, "hour")
    end
  end

  context "#sku_display_name" do
    test "returns the number of cores plus 'core' when the product sku name starts with 'compute_d'" do
      [2, 4, 8, 16, 32].each do |core_num|
        usage_line_item_from_api = create_mock_twirp_usage_line_item(
          product_sku_name: "compute_d#{core_num}"
        ).data.usage_line_items[0]
        wrapped_line_item = Billing::Codespaces::UsageLineItemWrapper.new(usage_line_item_from_api)
        assert_equal(wrapped_line_item.sku_display_name, "Compute - #{core_num} core")
      end
    end

    test "returns the capitalized product sku name when the product sku name does not start with 'compute_d'" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "product"
      ).data.usage_line_items[0]
      wrapped_line_item = Billing::Codespaces::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.sku_display_name, "Product")
    end
  end

  context "#action_workflow_name" do
    test "return prebuild workflow name if sku name is prebuild storage" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "prebuild_storage"
      ).data.usage_line_items[0]
      wrapped_line_item = Billing::Codespaces::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.action_workflow_name, Codespaces::Prebuilds::WORKFLOW_SLUG.titleize)
    end

    test "return no workflow name if sku name is not prebuild storage" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "other product"
      ).data.usage_line_items[0]
      wrapped_line_item = Billing::Codespaces::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_nil(wrapped_line_item.action_workflow_name)
    end
  end
end
