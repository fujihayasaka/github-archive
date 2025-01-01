# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Platform::Api::NetUsageLineItemTest < GitHub::TestCase
  context "#to_json" do
    test "returns expected json for non org and repo requests" do
      Timecop.freeze("2025-08-24 00:01:00Z") do
        now = Time.now.utc.to_i
        raw_net_usage_line_item_data = {
          grossAmount: 100,
          product: "actions",
          quantity: 10,
          fullQuantity: 10,
          discountAmount: 10,
          netAmount: 90,
          appliedCostPerQuantity: 10,
          sku: "actions_linux",
          friendlySkuName: "Actions Linux",
          usageAt: now,
          unitType: "minute"
        }

        net_usage_line_item = Billing::Platform::Api::NetUsageLineItem.new(raw_net_usage_line_item_data, org_or_repo_request: false)

        expected_json = {
          grossAmount: 100,
          product: "actions",
          quantity: 10,
          fullQuantity: 10,
          discountAmount: 10,
          netAmount: 90,
          appliedCostPerQuantity: 10,
          sku: "actions_linux",
          friendlySkuName: "Actions Linux",
          usageAt: Time.at(0, now, :millisecond).utc,
          unitType: "minute"
        }

        assert_equal net_usage_line_item.to_json, expected_json
      end
    end

    test "returns expected json for org and repo requests" do
      Timecop.freeze("2025-08-24 00:01:00Z") do
        now = Time.now.utc.to_i
        raw_net_usage_line_item_data = {
          grossAmount: 100,
          product: "actions",
          quantity: 10,
          fullQuantity: 10,
          discountAmount: 10,
          netAmount: 90,
          appliedCostPerQuantity: 10,
          sku: "actions_linux",
          friendlySkuName: "Actions Linux",
          usageAt: now,
          unitType: "minute"
        }

        net_usage_line_item = Billing::Platform::Api::NetUsageLineItem.new(raw_net_usage_line_item_data, org_or_repo_request: true)

        expected_json = {
          grossAmount: 100,
          product: "actions",
          quantity: 10,
          fullQuantity: 10,
          # we don't have discounts available at the org and repo level, so we return nil
          discountAmount: nil,
          # we don't have net amounts available at the org and repo level, so we return nil
          netAmount: nil,
          appliedCostPerQuantity: 10,
          sku: "actions_linux",
          friendlySkuName: "Actions Linux",
          usageAt: Time.at(0, now, :millisecond).utc,
          unitType: "minute"
        }

        assert_equal net_usage_line_item.to_json, expected_json
      end
    end
  end
end
