# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditDecisionEngine::CustomerDetailsTest < GitHub::TestCase
  setup do
    @customer_details = CreditDecisionEngine::CustomerDetails.new(name: "Mona Lisa", address: "1 Infinite Loop", city: "Cupertino", country_code: "US")
  end

  test "generates hash of all required fields" do
    @customer_details.stubs(:postal_code).returns(" ")
    @customer_details.stubs(:state).returns(" ")
    @customer_details.stubs(:phone_number).returns(" ")
    hash = @customer_details.to_hash

    assert_equal 1, hash.keys.count, "expected CustomerDetails"
    assert_equal 4, hash[:CustomerDetails].keys.count, "expected Name, StreetAddress1, City, CountryCode"
  end

  test "generates hash of all fields" do
    @customer_details.stubs(:postal_code).returns("12345")
    @customer_details.stubs(:state).returns("Washington")
    @customer_details.stubs(:phone_number).returns("42")
    hash = @customer_details.to_hash

    assert_equal 1, hash.keys.count, "expected CustomerDetails"
    assert_equal 7, hash[:CustomerDetails].keys.count, "expected Name, StreetAddress1, City, CountryCode, PostalCode, State, PhoneNumber"
  end

  test "validates no errors when all required fields are valid" do
    errors = @customer_details.validate

    assert_predicate errors, :empty?
    assert_predicate @customer_details.postal_code, :blank?
    assert_predicate @customer_details.state, :blank?
    assert_predicate @customer_details.phone_number, :blank?
  end

  test "validates no errors when all optional fields are valid" do
    @customer_details.stubs(:postal_code).returns("12345")
    @customer_details.stubs(:state).returns("Washington")
    @customer_details.stubs(:phone_number).returns("42")

    errors = @customer_details.validate

    assert_predicate errors, :empty?
  end

  test "validates name" do
    @customer_details.stubs(:name).returns(" ").then.returns("x" * 241)

    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "Name must be a string with a maximum of 240 characters"

    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "Name must be a string with a maximum of 240 characters"
  end

  test "validates address" do
    @customer_details.stubs(:address).returns(" ").then.returns("x" * 71)

    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "Address must be a string with a maximum of 70 characters"

    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "Address must be a string with a maximum of 70 characters"
  end

  test "validates city" do
    @customer_details.stubs(:city).returns(" ").then.returns("x" * 51)

    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "City must be a string with a maximum of 50 characters"

    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "City must be a string with a maximum of 50 characters"
  end

  test "validates country_code" do
    @customer_details.stubs(:country_code).returns(" ").then.returns("x" * 3)

    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "Country code must be a string with a maximum of 2 characters"

    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "Country code must be a string with a maximum of 2 characters"
  end

  test "validates postal_code" do
    @customer_details.stubs(:postal_code).returns(" ").then.returns("x" * 11)

    errors = @customer_details.validate

    assert_predicate errors, :empty?

    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "Postal code must be a string with a maximum of 10 characters"
  end

  test "validates state" do
    @customer_details.stubs(:country_code).returns("US")
    @customer_details.stubs(:state).returns(" ")

    errors = @customer_details.validate

    assert_predicate errors, :empty?

    @customer_details.stubs(:state).returns("Mona State")
    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "State must be a valid US state or CA province"

    @customer_details.stubs(:country_code).returns("YE")
    @customer_details.stubs(:state).returns("x" * 101)
    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "State must be a string with a maximum of 100 characters"
  end

  test "validates phone_number" do
    @customer_details.stubs(:phone_number).returns(" ").then.returns("x" * 33)

    errors = @customer_details.validate

    assert_predicate errors, :empty?

    errors = @customer_details.validate

    assert_equal 1, errors.size
    assert_includes errors, "Phone number must be a string with a maximum of 32 characters"
  end
end
