# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SharedStorage::UsageLineItemWrapperTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  fixtures do
    @repo = create(:repository)
  end

  context "#aggregate_effective_at" do
    test "returns the aggregate_effective_at when it is present" do
      usage_at = (GitHub::Billing.today - 1.day).to_time
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i)
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::SharedStorage::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.aggregate_effective_at, usage_at)
    end
  end

  context "#size_in_bytes" do
    test "returns the size_in_bytes when it is present" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        quantity: 2.gigabytes
      ).data.usage_line_items[0]
      wrapped_line_item = Billing::SharedStorage::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.size_in_bytes, 2.gigabytes)
    end
  end
end
