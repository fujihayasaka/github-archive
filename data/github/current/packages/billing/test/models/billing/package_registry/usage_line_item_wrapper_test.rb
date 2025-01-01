# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PackageRegistry::UsageLineItemWrapperTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers
  include GitHub::ComponentTestHelpers

  fixtures do
    @owner = create(:organization)
    @repo = create(:repository)
    @package = create(:registry_package, owner: @owner, repository: @repo)
  end

  context "#downloaded_at" do
    test "returns the downloaded_at time from a line item" do
      usage_at = (GitHub::Billing.today - 1.day).to_time
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        usage_at: Google::Protobuf::Timestamp.new(seconds: usage_at.to_i)
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::PackageRegistry::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.downloaded_at, usage_at.to_time.utc)
    end
  end

  context "#registry_package_id" do
    test "returns the registry_package_id from a line item" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        custom_fields: {
          "package.id" => @package.id.to_s
        }
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::PackageRegistry::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.registry_package_id, @package.id)
    end
  end

  context "#size_in_bytes" do
    test "returns the size_in_bytes from a line item" do
      usage_line_item_from_api = create_mock_twirp_usage_line_item(
        quantity: 512.megabytes
      ).data.usage_line_items[0]

      wrapped_line_item = Billing::PackageRegistry::UsageLineItemWrapper.new(usage_line_item_from_api)
      assert_equal(wrapped_line_item.size_in_bytes, 512.megabytes)
    end
  end
end
