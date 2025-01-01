# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Usage::FetchProductUsageTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  def setup
    @user = create(:user)
    @usage = build(:billing_account_usage)
  end

  test "returns Success with the account's product usage when the API request is successful" do
    args = {
      account: @user,
      products: [:actions]
    }

    mock_list_product_usage_response(additional_product_usages: @usage.product_usages.map(&:raw_product_usage))

    response = Billing::Usage::FetchProductUsage.new(**args).call

    assert response.success?
    assert response.content.is_a?(Array)

    usage = response.content
    usage.each { |usage| assert usage.is_a?(Billing::Usage::ProductUsage) }
  end

  test "returns Error with a BillingClientError when the API request fails" do
    args = {
      account: @user,
      products: [:actions]
    }

    mock_list_product_usage_response_error

    response = Billing::Usage::FetchProductUsage.new(**args).call

    assert response.error?
    assert response.content.is_a?(Billing::Api::ClientWrapper::BillingClientError)
  end
end
