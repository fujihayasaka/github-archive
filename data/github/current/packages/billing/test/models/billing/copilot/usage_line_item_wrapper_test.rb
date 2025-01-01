# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Copilot::UsageLineItemWrapperTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers
  include GitHub::ComponentTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner
  end

  context "#end_time" do
    test "returns the end_time from a line item" do
      usage_at = (GitHub::Billing.today - 1.day).to_time
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i),
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Copilot::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.end_time, usage_at.to_time.utc)
    end
  end

  context "#usage" do
    test "returns the correct usage" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "copilot_for_business",
        quantity: 10
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Copilot::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.usage, 10)
    end
  end

  context "#sku_display_name" do
    test "returns the correct sku when it is copilot for business" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "copilot_for_business",
        quantity: 10
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Copilot::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.sku_display_name, "Copilot Business")
    end

    test "returns the correct sku when it is copilot enterprise" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "copilot_enterprise",
        quantity: 10
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Copilot::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.sku_display_name, "Copilot Enterprise")
    end

    test "returns the correct sku when it is copilot standalone" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "copilot_standalone",
        quantity: 10
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Copilot::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.sku_display_name, "Copilot Business")
    end

    test "returns the correct sku when it lacks a valid sku" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        product_sku_name: "wrong_sku",
        quantity: 10
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Copilot::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.sku_display_name, "Copilot")
    end

    test "returns the correct sku when it lacks a sku" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        quantity: 10
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::Copilot::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.sku_display_name, "Copilot")
    end
  end
end
