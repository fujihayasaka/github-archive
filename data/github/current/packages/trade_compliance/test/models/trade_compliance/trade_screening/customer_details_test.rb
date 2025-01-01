# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class CustomerDetailsTest < GitHub::TestCase
    setup do
      @individual_details = T.let(CustomerDetails.new(id: "1", first_name: "Mona", last_name: "Lisa", address1: "1 Infinity Loop", city: "San Francisco", region: "California", country_code: "US", postal_code: "94105"), CustomerDetails)
      @business_details = T.let(CustomerDetails.new(id: "2", entity_name: "OctoFactory", address1: "1 Infinity Loop", city: "San Francisco", region: "California", country_code: "US", postal_code: "94105"), CustomerDetails)
    end

    test "generates hash of all required individual fields" do
      errors = @individual_details.validate(account_type: AccountType::Individual)
      hash = @individual_details.to_hash(account_type: AccountType::Individual)

      assert_predicate errors, :empty?
      assert_equal 5, hash.keys.count, "expected ReqId, FullName, FirstName, LastName, Addrs"
      assert_equal 6, hash.dig(:Addrs, :Addr).first.keys.count, "expected AdTyp, Ad1, Cty, Rgn, Pc, Ctry"
    end

    test "generates hash of all required business fields" do
      errors = @business_details.validate(account_type: AccountType::Business)
      hash = @business_details.to_hash(account_type: AccountType::Business)

      assert_predicate errors, :empty?
      assert_equal 3, hash.keys.count, "expected ReqId, FullName, Addrs"
      assert_equal 6, hash.dig(:Addrs, :Addr).first.keys.count, "expected AdTyp, Ad1, Cty, Rgn, Pc, Ctry"
    end

    context "#validations" do
      test "validates id" do
        @individual_details.stubs(:id).returns(" ").then.returns("x" * 256)

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Id can't be blank"

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Id is too long (maximum is 255 characters)"
      end

      test "validates first name" do
        @individual_details.stubs(:first_name).returns(" ")

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "First name can't be blank"

        @individual_details.stubs(:first_name).returns("x")

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "First name is too short"

        @individual_details.stubs(:first_name).returns("x" * 256)

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "First name is too long (maximum is 255 characters)"
      end

      test "validates last name" do
        @individual_details.stubs(:last_name).returns(" ")

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Last name can't be blank"

        @individual_details.stubs(:last_name).returns("x")

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Last name is too short"

        @individual_details.stubs(:last_name).returns("x" * 256)

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Last name is too long (maximum is 255 characters)"
      end

      test "validates entity name" do
        @business_details.stubs(:entity_name).returns(" ").then.returns("x" * 801)

        errors = @business_details.validate(account_type: AccountType::Business)

        assert_equal 1, errors.size
        assert_includes errors, "Entity name can't be blank"

        errors = @business_details.validate(account_type: AccountType::Business)

        assert_equal 1, errors.size
        assert_includes errors, "Entity name is too long (maximum is 800 characters)"
      end

      test "validates vat code" do
        @business_details.stubs(:country_code).returns("AE")
        @business_details.stubs(:vat_code).returns(" ")

        errors = @business_details.validate(account_type: AccountType::Business)

        assert_equal 1, errors.size
        assert_includes errors, "Vat code can't be blank"

        @business_details.stubs(:vat_code).returns("x" * 51)

        errors = @business_details.validate(account_type: AccountType::Business)

        assert_equal 1, errors.size
        assert_includes errors, "Vat code is too long (maximum is 50 characters)"
      end

      test "validates address1" do
        @individual_details.stubs(:address1).returns(" ").then.returns("x" * 129)

        # validate blank condition
        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Address1 can't be blank"

        # validate length condition
        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Address1 is too long (maximum is 128 characters)"
      end

      test "validates address2" do
        @individual_details.stubs(:address2).returns(" ").then.returns("x" * 129)

        # validate blank condition
        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_predicate errors, :empty?

        # validate length condition
        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Address2 is too long (maximum is 128 characters)"
      end

      test "validates city" do
        @individual_details.stubs(:city).returns(" ").then.returns("x" * 171)

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "City can't be blank"

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "City is too long (maximum is 170 characters)"
      end

      test "validates region" do
        @individual_details.stubs(:country_code).returns("US")
        @individual_details.stubs(:region).returns(" ")

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Region can't be blank"

        @individual_details.stubs(:region).returns("Mona State")
        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_predicate errors, :empty?

        @individual_details.stubs(:country_code).returns("YE")
        @individual_details.stubs(:region).returns("x" * 256)
        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Region is too long (maximum is 255 characters)"
      end

      test "validates country_code" do
        @individual_details.stubs(:country_code).returns(" ")

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Country code can't be blank"

        @individual_details.stubs(:country_code).returns("x" * 3)

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Country code is too long (maximum is 2 characters)"
      end

      test "validates postal_code" do
        @individual_details.stubs(:country_code).returns("US")
        @individual_details.stubs(:postal_code).returns(" ")

        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Postal code can't be blank"

        @individual_details.stubs(:country_code).returns("YE")
        @individual_details.stubs(:postal_code).returns("x" * 11)
        errors = @individual_details.validate(account_type: AccountType::Individual)

        assert_equal 1, errors.size
        assert_includes errors, "Postal code is too long (maximum is 10 characters)"
      end
    end
  end
end
