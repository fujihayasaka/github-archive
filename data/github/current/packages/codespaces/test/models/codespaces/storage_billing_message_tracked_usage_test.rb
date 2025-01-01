# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesStorageBillingMessageTrackedUsageTest < GitHub::TestCase
  setup do
    @usage_data = {
      "sku" => "basicLinux32gb",
      "usage" => rand(0..1800.0),
      "size" => rand(0..1800),
      "sizeInKb" => rand(0..1800),
    }
  end

  context "#size_in_bytes" do
    test "generate from sizeInKb" do
      tracked_usage = Codespaces::StorageBillingMessageTrackedUsage.new(usage_data: @usage_data, codespace_guid: "", usage_type: Codespaces::BillingMessageTrackedUsage::STORAGE_USAGE_TYPE)
      assert_equal tracked_usage.size_in_bytes, @usage_data["sizeInKb"] * Numeric::KILOBYTE
    end
  end

  context "#computed_usage_in_gb_month" do
    test "compute non-zero usage for sub 1-GB storage" do
      usage_data = {
        "sku" => "basicLinux32gb",
        "usage" => rand(0..1800.0),
        "size" => rand(0..1800),
        "sizeInKb" => rand(1000..1800),
      }
      tracked_usage = Codespaces::StorageBillingMessageTrackedUsage.new(usage_data: usage_data, codespace_guid: "", usage_type: Codespaces::BillingMessageTrackedUsage::STORAGE_USAGE_TYPE)
      assert tracked_usage.computed_usage_in_gb_month > 0.0
    end
  end
end
