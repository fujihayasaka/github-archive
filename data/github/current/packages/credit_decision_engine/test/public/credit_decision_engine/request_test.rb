# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditDecisionEngine::RequestTest < GitHub::TestCase
  setup do
    @customer_details = CreditDecisionEngine::CustomerDetails.new(name: "Mona Lisa", address: "1 Infinite Loop", city: "Cupertino", postal_code: "95014", country_code: "US")
  end

  test "generates hash of all fields" do
    hash = CreditDecisionEngine::Request.build_request(reference_id: "123", customer_details: @customer_details, currency_code: "USD", amount: 100.123)

    assert_equal 5, hash.keys.count, "expected LobName, SourceReferenceID, CurrencyCode, Amount, CustomerDetails"
    assert_equal 5, hash[:CustomerDetails].keys.count, "expected Name, StreetAddress1, City, PostalCode, CountryCode"
  end

  test "validates reference_id" do
    assert_raises_with_message CreditDecisionEngine::RequestError, "Reference number: , errors: Reference ID must be a string with a maximum of 20 characters" do
      CreditDecisionEngine::Request.build_request(reference_id: "", customer_details: @customer_details, currency_code: "USD", amount: 100.0)
    end

    assert_raises_with_message CreditDecisionEngine::RequestError, "Reference number: xxxxxxxxxxxxxxxxxxxxx, errors: Reference ID must be a string with a maximum of 20 characters" do
      CreditDecisionEngine::Request.build_request(reference_id: "x" * 21, customer_details: @customer_details, currency_code: "USD", amount: 100.0)
    end
  end

  test "validates currency_code" do
    assert_raises_with_message CreditDecisionEngine::RequestError, "Reference number: 123, errors: Currency code must be a string with a maximum of 3 characters" do
      CreditDecisionEngine::Request.build_request(reference_id: "123", customer_details: @customer_details, currency_code: "", amount: 100.0)
    end

    assert_raises_with_message CreditDecisionEngine::RequestError, "Reference number: 123, errors: Currency code must be a string with a maximum of 3 characters" do
      CreditDecisionEngine::Request.build_request(reference_id: "123", customer_details: @customer_details, currency_code: "x" * 4, amount: 100.0)
    end
  end

  context "#amount" do
    test "validates amount is no more than 13 digits" do
      assert_raises_with_message CreditDecisionEngine::RequestError, "Reference number: 123, errors: Amount must be a decimal with a maximum of 13 digits" do
        CreditDecisionEngine::Request.build_request(reference_id: "123", customer_details: @customer_details, currency_code: "USD", amount: 10.pow(13) + 0.02)
      end
    end

    test "validates amount is not 0" do
      assert_raises_with_message CreditDecisionEngine::RequestError, "Reference number: 123, errors: Must provide a valid non-zero positive amount" do
        CreditDecisionEngine::Request.build_request(reference_id: "123", customer_details: @customer_details, currency_code: "USD", amount: 0)
      end
    end

    test "validates amount is positive amount" do
      assert_raises_with_message CreditDecisionEngine::RequestError, "Reference number: 123, errors: Must provide a valid non-zero positive amount" do
        CreditDecisionEngine::Request.build_request(reference_id: "123", customer_details: @customer_details, currency_code: "USD", amount: -2)
      end
    end
  end

  test "validates notes" do
    assert_raises_with_message CreditDecisionEngine::RequestError, "Reference number: 123, errors: Notes must be a string with a maximum of 1000 characters" do
      CreditDecisionEngine::Request.build_request(reference_id: "123", customer_details: @customer_details, currency_code: "USD", amount: 100.0, notes: "x" * 1001)
    end
  end
end
