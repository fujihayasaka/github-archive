# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::InvoicedCustomerBillingAddressTest < GitHub::TestCase
  context "#full_name" do
    test "concatenates the first and last names" do
      customer = build_customer_information(FirstName: "John", LastName: "Doe")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).full_name

      assert_equal "John Doe", result
    end

    test "strips whitespace before and after the name" do
      customer = build_customer_information(FirstName: " John ", LastName: " Doe ")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).full_name

      assert_equal "John Doe", result
    end

    test "does not strip whitespace for multi-part names" do
      customer = build_customer_information(FirstName: "Mary Ann", LastName: "Perry Smith")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).full_name

      assert_equal "Mary Ann Perry Smith", result
    end

    test "returns nil if customer is nil" do
      customer = Sponsors::BillingContactResult.error("error")
      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).full_name

      assert_nil result
    end
  end

  context "#first_name" do
    test "returns the first name" do
      customer = build_customer_information(FirstName: "Mary Ann")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).first_name

      assert_equal "Mary Ann", result
    end

    test "strips whitespace before and after the name" do
      customer = build_customer_information(FirstName: "   Mary Ann ")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).first_name

      assert_equal "Mary Ann", result
    end

    test "returns nil if customer is nil" do
      customer = Sponsors::BillingContactResult.error("error")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).first_name

      assert_nil result
    end

    test "returns nil if key does not exist" do
      customer = build_customer_information(LastName: "Santiago")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).first_name

      assert_nil result
    end
  end

  context "#last_name" do
    test "returns the last name" do
      customer = build_customer_information(LastName: "Perry Smith")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).last_name

      assert_equal "Perry Smith", result
    end

    test "strips whitespace before and after the name" do
      customer = build_customer_information(LastName: "   Perry Smith ")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).last_name

      assert_equal "Perry Smith", result
    end

    test "returns nil if customer is nil" do
      customer = Sponsors::BillingContactResult.error("error")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).last_name

      assert_nil result
    end

    test "returns nil if key does not exist" do
      customer = build_customer_information(FirstName: "Aaron")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).last_name

      assert_nil result
    end
  end

  context "#street_address_1" do
    test "returns the first street address" do
      customer = build_customer_information(Address1: "234 Main St.")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).street_address_1

      assert_equal "234 Main St.", result
    end

    test "returns nil if customer is nil" do
      customer = Sponsors::BillingContactResult.error("error")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).street_address_1

      assert_nil result
    end

    test "returns nil if key does not exist" do
      customer = build_customer_information(Address2: "2nd Floor")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).street_address_1

      assert_nil result
    end
  end

  context "#street_address_2" do
    test "returns the second street address" do
      customer = build_customer_information(Address2: "234 Main St.")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).street_address_2

      assert_equal "234 Main St.", result
    end

    test "returns nil if customer is nil" do
      customer = Sponsors::BillingContactResult.error("error")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).street_address_2

      assert_nil result
    end

    test "returns nil if key does not exist" do
      customer = build_customer_information(Address1: "123 Main St")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).street_address_2

      assert_nil result
    end
  end

  context "#region" do
    test "returns the state appreviation for states in the United States" do
      customer = build_customer_information(State: "Massachusetts", Country: "United States")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).region

      assert_equal "MA", result
    end

    test "returns the state abbrevation for different variations of the United States" do
      customer1 = build_customer_information(State: "Massachusetts", Country: "United States of America")
      customer2 = build_customer_information(State: "Massachusetts", Country: "united states")
      customer3 = build_customer_information(State: "Massachusetts", Country: "U.S.A")
      customer4 = build_customer_information(State: "Massachusetts", Country: "US")

      result1 = Sponsors::InvoicedCustomerBillingAddress.new(customer1).region
      result2 = Sponsors::InvoicedCustomerBillingAddress.new(customer2).region
      result3 = Sponsors::InvoicedCustomerBillingAddress.new(customer3).region
      result4 = Sponsors::InvoicedCustomerBillingAddress.new(customer4).region

      assert_equal "MA", result1
      assert_equal "MA", result2
      assert_equal "MA", result3
      assert_equal "MA", result4
    end

    test "returns the full state value if no country is specified" do
      customer = build_customer_information(State: "Alabama")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).region

      assert_equal "Alabama", result
    end

    test "returns the full state value for countries outside of the United States" do
      customer = build_customer_information(State: "Alberta", Country: "Canada")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).region

      assert_equal "Alberta", result
    end

    test "returns nil if customer is nil" do
      customer = Sponsors::BillingContactResult.error("error")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).region

      assert_nil result
    end

    test "returns nil if key does not exist" do
      customer = build_customer_information(Address1: "123 Main St")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).region

      assert_nil result
    end
  end

  context "#postal_code" do
    test "returns the postal code" do
      customer = build_customer_information(PostalCode: "12345-6789")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).postal_code

      assert_equal "12345-6789", result
    end

    test "returns nil if customer is nil" do
      customer = Sponsors::BillingContactResult.error("error")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).postal_code

      assert_nil result
    end

    test "returns nil if key does not exist" do
      customer = build_customer_information(Address1: "123 Main St")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).postal_code

      assert_nil result
    end
  end

  context "#country" do
    test "returns the country" do
      customer = build_customer_information(Country: "United States")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).country

      assert_equal "United States", result
    end

    test "returns nil if customer is nil" do
      customer = Sponsors::BillingContactResult.error("error")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).country

      assert_nil result
    end

    test "returns nil if key does not exist" do
      customer = build_customer_information(Address1: "123 Main St")

      result = Sponsors::InvoicedCustomerBillingAddress.new(customer).country

      assert_nil result
    end
  end

  def build_customer_information(info)
    Sponsors::BillingContactResult.success(info.stringify_keys)
  end
end
