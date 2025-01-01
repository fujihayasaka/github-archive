# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Usage::CodespacesCalculatorTest < GitHub::BillingTestCase
  include ::Billing::UsageTestHelpers
  include ::Billing::ApiTestHelpers

  setup do
    @user = create :user
  end

  context "#cost" do
    test "returns the sum of all total_historical_usage estimated costs" do
      mock_calculate_usage_quotes_response(usage_quotes: [
        { total_historical_usage: { estimated_cost: { subunits: 100 } } },
        { total_historical_usage: { estimated_cost: { subunits: 200 } } }
      ])

      assert_equal 3_00, Billing::Usage::CodespacesCalculator.new(billable_owner: @user).cost
    end

    test "raises when a Billing::Api::ClientWrapper::BillingClientError is returned" do
      mock_calculate_usage_quotes_response_error

      assert_raises Billing::Api::ClientWrapper::BillingClientError do
        Billing::Usage::CodespacesCalculator.new(billable_owner: @user).cost
      end
    end
  end
end
