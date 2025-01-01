# typed: true
# frozen_string_literal: true

require "test_helper"

class Taxamo::LookupResultTest < GitHub::TestCase

  context "#no_match?" do
    test "returns true with no match" do
      result = Taxamo::LookupResult.new
      assert_predicate result, :no_match?
    end

    test "returns true when there's an error" do
      result = Taxamo::LookupResult.new(error: Taxamo::LookupResult::Error.new(messages: ["error"], error_code: "error"))
      assert_predicate result, :no_match?
    end

    test "returns false with a match" do
      result = Taxamo::LookupResult.new(match: Taxamo::LookupResult::SimilarMatch.new(
        street_name: "123 Main St",
        city: "Springfield",
        region: "IL",
        postal_code: "62701",
        county: "Sangamon",
      ))
      refute_predicate result, :no_match?
    end

    test "returns false with an exact match" do
      result = Taxamo::LookupResult.new(exact_match: true)
      refute_predicate result, :no_match?
    end
  end

  context "#suggested_match?" do
    test "returns true with a suggested match" do
      result = Taxamo::LookupResult.new(match: Taxamo::LookupResult::SimilarMatch.new(
        street_name: "123 Main St",
        city: "Springfield",
        region: "IL",
        postal_code: "62701",
        county: "Sangamon",
      ))
      assert_predicate result, :suggested_match?
    end

    test "returns false with an exact match" do
      result = Taxamo::LookupResult.new(exact_match: true, match: Taxamo::LookupResult::SimilarMatch.new(
        street_name: "123 Main St",
        city: "Springfield",
        region: "IL",
        postal_code: "62701",
        county: "Sangamon",
      ))
      refute_predicate result, :suggested_match?
    end
  end

  context "#exact_match?" do
    test "returns true with an exact match" do
      result = Taxamo::LookupResult.new(exact_match: true, match: Taxamo::LookupResult::SimilarMatch.new(
        street_name: "123 Main St",
        city: "Springfield",
        region: "IL",
        postal_code: "62701",
        county: "Sangamon",
      ))
      assert_predicate result, :exact_match?
    end

    test "returns false with a suggested match" do
      result = Taxamo::LookupResult.new(match: Taxamo::LookupResult::SimilarMatch.new(
        street_name: "123 Main St",
        city: "Springfield",
        region: "IL",
        postal_code: "62701",
        county: "Sangamon",
      ))
      refute_predicate result, :exact_match?
    end
  end
end
