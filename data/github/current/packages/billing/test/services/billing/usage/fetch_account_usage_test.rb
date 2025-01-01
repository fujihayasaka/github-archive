# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Usage::FetchAccountUsageTest < GitHub::TestCase
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

    Meuse::Client.any_instance.expects(:list_account_usage).returns(
      Twirp::ClientResp.new(
        data: Meuse::Services::V1::ListAccountUsageResponse.new(account_usage: [@usage.raw_account_usage]),
        error: nil
      )
    )

    response = Billing::Usage::FetchAccountUsage.new(**args).call

    assert response.success?
    assert response.content.is_a?(Array)

    quotes = response.content
    quotes.each { |usage| assert usage.is_a?(Billing::Usage::AccountUsage) }
  end

  test "returns Error with a BillingClientError when the API request fails" do
    args = {
      account: @user,
      products: [:actions]
    }

    mock_list_account_usage_response_error

    response = Billing::Usage::FetchAccountUsage.new(**args).call

    assert response.error?
    assert response.content.is_a?(Billing::Api::ClientWrapper::BillingClientError)
  end
end
