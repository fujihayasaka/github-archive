# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  module Public
    class ValidateAddressTest < GitHub::BillingTestCase
      include Billing::AddressLookupTestHelpers

      test "returns valid if response is valid" do
        Taxamo::Client.any_instance.stubs(:address_lookup).returns(exact_tax_address_lookup_result)
        response = Billing::Public::validate_address(street: "123 Main", city: "San Francisco", region: "CA", postal_code: "94107-1234")
        assert response.valid
        assert response.error.blank?
      end

      test "returns generic error message if no match found" do
        Taxamo::Client.any_instance.stubs(:address_lookup).returns(no_tax_address_lookup_result)
        response = Billing::Public::validate_address(street: "123 No Exist", city: "Not a City", region: "CA", postal_code: "12345")
        refute response.valid
        assert_equal response.error, "The address entered is invalid or cannot be found. Please make corrections and resave your billing information. Retrying with a 9-digit zip code may resolve the issue."
      end

      test "returns error message if problem with client occurs" do
        Taxamo::Client.any_instance.stubs(:address_lookup).returns(address_lookup_failed_result)
        response = Billing::Public::validate_address(street: "123 Main", city: "San Francisco", region: "CA", postal_code: "94107-1234")
        refute response.valid
        assert_equal response.error, "Something went wrong, please try again."
      end

      test "returns suggestions in error response if suggested matches found" do
        Taxamo::Client.any_instance.stubs(:address_lookup).returns(suggested_tax_address_lookup_result(
          suggested_street: "123 Main",
          suggested_city: "San Francisco",
          suggested_region: "California",
          suggested_postal_code: "94107"
        ))
        response = Billing::Public::validate_address(street: "123 Main", city: "San Fran", region: "Colorado", postal_code: "94107")
        refute response.valid
        assert_equal response.error, "The address entered did not match the postal code. Did you mean San Francisco, California?"
      end

      test "returns suggested postal code" do
        suggested_postal_code = "90210-1234"
        Taxamo::Client.any_instance.stubs(:address_lookup).returns(suggested_tax_address_lookup_result(
          suggested_street: "123 Main",
          suggested_city: "San Francisco",
          suggested_region: "California",
          suggested_postal_code: suggested_postal_code
        ))
        response = Billing::Public::validate_address(street: "123 Main", city: "San Francisco", region: "California", postal_code: "94107")
        assert response.valid
        assert response.error.blank?
        assert_equal response.suggested_postal_code, suggested_postal_code
      end
    end
  end
end
