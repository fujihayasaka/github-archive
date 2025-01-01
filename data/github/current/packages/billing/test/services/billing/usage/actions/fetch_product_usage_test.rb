# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Usage::Actions::FetchProductUsageTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  def setup
    @user = create(:user)
    @usage = build(:billing_account_usage)
  end

  test "returns Success with the account's product usage when the API request is successful" do
    args = { account: @user }

    mock_list_product_usage_response(additional_product_usages: @usage.product_usages.map(&:raw_product_usage))

    response = Billing::Usage::Actions::FetchProductUsage.new(**args).call

    assert response.success?
    assert response.content.is_a?(Billing::Usage::ActionsUsage)

    usage = response.content

    assert_equal usage.windows, @usage.product_usages.detect { |p| p.product_sku_name == "windows" }&.quantity
    assert_equal usage.macos, @usage.product_usages.detect { |p| p.product_sku_name == "macos" }&.quantity
    assert_equal usage.ubuntu, @usage.product_usages.detect { |p| p.product_sku_name == "linux" }&.quantity
    assert_equal usage.total, @usage.product_usages.sum(&:quantity)
  end

  test "returns Error with zeroed actions usage when the API request fails" do
    args = { account: @user }

    mock_list_product_usage_response_error

    response = Billing::Usage::Actions::FetchProductUsage.new(**args).call

    assert response.error?
    assert response.content.is_a?(Billing::Usage::ActionsUsage)

    usage = response.content

    assert_equal usage.windows, 0
    assert_equal usage.macos, 0
    assert_equal usage.ubuntu, 0
    assert_equal usage.total, 0
  end
end
