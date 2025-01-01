# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesBillingMessageTrackedUsageTest < GitHub::TestCase
  setup do
    @usage_data = {
      "sku" => "basicLinux32gb",
      "usage" => rand(0..1800.0),
    }
    @codespace_guid = "randomcharacters"
  end

  context "validations" do
    test "valid" do
      tracked_usage = Codespaces::BillingMessageTrackedUsage.new(
        usage_data: @usage_data,
        codespace_guid: @codespace_guid,
        usage_type: Codespaces::BillingMessageTrackedUsage::COMPUTE_USAGE_TYPE
      )
      assert tracked_usage.valid?
    end

    test "invalid with missing guid" do
      tracked_usage = Codespaces::BillingMessageTrackedUsage.new(
        usage_data: @usage_data,
        codespace_guid: nil,
        usage_type: Codespaces::BillingMessageTrackedUsage::COMPUTE_USAGE_TYPE
      )
      refute tracked_usage.valid?
    end

    test "invalid with missing usage type" do
      tracked_usage = Codespaces::BillingMessageTrackedUsage.new(
        usage_data: @usage_data,
        codespace_guid: @codespace_guid,
        usage_type: nil
      )
      refute tracked_usage.valid?
    end

    test "invalid with no usage" do
      @usage_data["usage"] = -1
      tracked_usage = Codespaces::BillingMessageTrackedUsage.new(
        usage_data: @usage_data,
        codespace_guid: @codespace_guid,
        usage_type: Codespaces::BillingMessageTrackedUsage::COMPUTE_USAGE_TYPE
      )
      refute tracked_usage.valid?
    end

    test "invalid with unexpected sku" do
      @usage_data["sku"] = "randomstring"
      tracked_usage = Codespaces::BillingMessageTrackedUsage.new(
        usage_data: @usage_data,
        codespace_guid: @codespace_guid,
        usage_type: Codespaces::BillingMessageTrackedUsage::COMPUTE_USAGE_TYPE
      )
      refute tracked_usage.valid?
    end
  end

  context "#generate_map" do
    test "returns a map of codespace guid to tracked usages" do
      codespace = build(:codespace)
      billing_message = build(
        :codespace_ephemeral_billing_message,
        codespaces: [codespace],
        codespace_plan_id: T.must(Codespaces::Plan.last).id
      )
      tracked_usage_map = Codespaces::BillingMessageTrackedUsage.generate_map(billing_message)
      resource_usage = billing_message.environments[0]["resourceUsage"]
      compute_usage = resource_usage["compute"][0]
      storage_usage = resource_usage["storage"][0]

      assert tracked_usage_map.key?(codespace.guid)
      usages = tracked_usage_map[codespace.guid]
      assert_equal usages.length, 2

      valid_compute = usages.one? do |usage|
        usage.is_compute? && usage.billable_duration_in_seconds == compute_usage["usage"] && usage.sku_name == compute_usage["sku"]
      end
      assert valid_compute

      valid_storage = usages.one? do |usage|
        usage.is_storage? && usage.billable_duration_in_seconds == storage_usage["usage"] && usage.sku_name == storage_usage["sku"] && usage.size_in_kb == storage_usage["sizeInKb"]
      end
      assert valid_storage
    end
  end
end
