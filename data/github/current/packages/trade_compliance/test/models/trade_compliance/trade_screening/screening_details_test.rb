# typed: true
# frozen_string_literal: true

require "test_helper"

module TradeCompliance::TradeScreening
  class ScreeningDetailsTest < GitHub::TestCase
    setup do
      @individual_details = T.let(CustomerDetails.new(id: "IndName_IndAddr", first_name: "Mona", last_name: "Lisa", address1: "1 Infinity Loop", city: "San Francisco", region: "California", country_code: "US", postal_code: "94105"), CustomerDetails)
      @individual_screening_details = T.let(ScreeningDetails.new(account_type: AccountType::Individual, external_id: SecureRandom.uuid), ScreeningDetails)
      @individual_screening_details.add_customer_details(details: @individual_details)

      @business_details = T.let(CustomerDetails.new(id: "2", entity_name: "OctoFactory", address1: "1 Infinity Loop", city: "San Francisco", region: "California", country_code: "US", postal_code: "94105"), CustomerDetails)
      @business_screening_details = T.let(ScreeningDetails.new(account_type: AccountType::Business, external_id: SecureRandom.uuid), ScreeningDetails)
      @business_screening_details.add_customer_details(details: @business_details)
    end

    test "generates hash of all required individual fields" do
      errors = @individual_screening_details.validate
      hash = @individual_screening_details.to_hash

      assert_predicate errors, :empty?
      assert_equal 1, hash.keys.count, "expected ScrReqsEnv"
      assert_equal 7, hash.dig(:ScrReqsEnv).keys.count, "expected EId, DT, CohortCode, Prov, CustTyp, ExternalRefID, ScrReqs"
      assert_equal "IND", hash.dig(:ScrReqsEnv, :CustTyp)
    end

    test "generates hash of all required business fields" do
      errors = @business_screening_details.validate
      hash = @business_screening_details.to_hash

      assert_predicate errors, :empty?
      assert_equal 1, hash.keys.count, "expected ScrReqsEnv"
      assert_equal 7, hash.dig(:ScrReqsEnv).keys.count, "expected EId, DT, CohortCode, Prov, CustTyp, ExternalRefID, ScrReqs"
      assert_equal "ORG", hash.dig(:ScrReqsEnv, :CustTyp)
    end

    context "#validations" do
      test "validates external id" do
        @individual_screening_details.stubs(:external_id).returns(" ").then.returns("x" * 41)

        errors = @individual_screening_details.validate

        assert_equal 1, errors.size
        assert_includes errors, "External id must be a string with a maximum of 40 characters"

        errors = @individual_screening_details.validate

        assert_equal 1, errors.size
        assert_includes errors, "External id must be a string with a maximum of 40 characters"
      end

      test "validates customer details" do
        @individual_details.stubs(:first_name).returns(nil)
        @individual_screening_details.stubs(:customer_details).returns([]).then.returns([@individual_details])

        errors = @individual_screening_details.validate

        assert_equal 1, errors.size
        assert_includes errors, "Must add at least one customer details"

        errors = @individual_screening_details.validate

        assert_equal 1, errors.size
        assert_includes errors, "Customer details id IndName_IndAddr: First name can't be blank"
      end

      test "validates individual customer details contain at least one detail with the ID `IndName_IndAddr`" do
        @individual_details.stubs(:id).returns("1")

        errors = @individual_screening_details.validate

        assert_equal 1, errors.size
        assert_includes errors, "Must add at least one customer details with ID 'IndName_IndAddr'"

        more_details = T.let(CustomerDetails.new(id: "IndName_IndAddr", first_name: "Mona", last_name: "Lisa", address1: "1 Infinity Loop", city: "San Francisco", region: "California", country_code: "US", postal_code: "94105"), CustomerDetails)
        @individual_screening_details.add_customer_details(details: more_details)

        errors = @individual_screening_details.validate

        assert_predicate errors, :empty?
      end
    end
  end
end
