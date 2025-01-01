# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Usage::CalculateUsageQuotesTest < GitHub::TestCase
  include ::Billing::ApiTestHelpers

  def setup
    @user = create(:user)
  end

  test "returns Success with usage quotes when the API request is successful" do
    proposed_usage = [{
      proposed_quantity:    100,
      entitlement_quantity: 0,
      product_name:         "actions",
      product_sku_name:     "linux",
    }]

    args = {
      account:        @user,
      proposed_usage: proposed_usage,
    }

    mock_calculate_usage_quotes_response(proposed_usage: proposed_usage)

    response = Billing::Usage::CalculateUsageQuotes.new(**args).call

    assert response.success?
    assert response.content.is_a?(Array)

    quotes = response.content
    quotes.each { |quote| assert quote.is_a?(Billing::Usage::UsageQuote) }
  end

  test "returns Error with a BillingClientError when the API request fails" do
    proposed_usage = [{
      proposed_quantity:    0,
      entitlement_quantity: 0,
      product_name:         "not a product",
      product_sku_name:     "linux",
    }]

    args = {
      account:        @user,
      proposed_usage: proposed_usage,
    }

    mock_calculate_usage_quotes_response_error

    response = Billing::Usage::CalculateUsageQuotes.new(**args).call

    assert response.error?
    assert response.content.is_a?(Billing::Api::ClientWrapper::BillingClientError)
  end
end
