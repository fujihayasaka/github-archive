# typed: true
# frozen_string_literal: true

require "test_helper"

class Taxamo::ClientTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  setup do
    @stubbed_url = "#{Taxamo::Client::BASE_URL}/#{Taxamo::Client::ADDRESS_VALIDATION_ENDPOINT}"
    VCR.configure do |c|
      c.filter_sensitive_data("<TAXAMO_API_PRIVATE_TOKEN>") { GitHub.taxamo_api_private_token }
    end
    @taxamo_client = Taxamo::Client.new(private_token: GitHub.taxamo_api_private_token)
  end

  context "#address_lookup" do
    test "returns an exact match when there's no lookup required" do
      VCR.use_cassette("taxamo/address_lookup/exact_match") do
        github_hq = ["88 Colin P Kelly Jr St", "San Francisco", "CA", "94107-2008"]

        result = @taxamo_client.address_lookup(*github_hq)
        assert result.exact_match?
      end
    end

    test "returns an error result when the address supplied is malformed" do
      VCR.use_cassette("taxamo/address_lookup/error_400") do
        malformed_address = ["88 Colin P Kelly Jr St", "San Francisco", "GG", "33333"]

        result = @taxamo_client.address_lookup(*malformed_address)
        assert result.error.present?
      end
    end

    test "returns a suggested match for misspelled addresses" do
      VCR.use_cassette("taxamo/address_lookup/similar_matches") do
        github_hq = ["88 Colen P Kelly Jr St", "San Francisco", "CA", "94107"]
        result = @taxamo_client.address_lookup(*github_hq)
        assert result.suggested_match?
        match = T.must(result.match)
        assert_equal "88 Colin P Kelly Jr St", match.street_name
        assert_equal "San Francisco", match.city
        assert_equal "CA", match.region
        assert_match /\A94107/, match.postal_code

        whitehouse = ["1600 Pencilvania Avenue NW", "Washington", "DC", "20500"]
        result = @taxamo_client.address_lookup(*whitehouse)
        assert result.suggested_match?
        match = T.must(result.match)
        assert_equal "1600 Pennsylvania Ave NW", match.street_name
        assert_equal "Washington", match.city
        assert_equal "DC", match.region
        assert_match /\A20500/, match.postal_code

        taxamo_hq = ["2301 Renaissance Blvd", "King of Russia", "PA", "19406"]
        result = @taxamo_client.address_lookup(*taxamo_hq)
        assert result.suggested_match?
        match = T.must(result.match)
        assert_equal "2301 Renaissance Blvd", match.street_name
        assert_equal "King Of Prussia", match.city
        assert_equal "PA", match.region
        assert_match /\A19406/, match.postal_code
      end
    end

    test "returns no match on invalid addresses" do
      VCR.use_cassette("taxamo/address_lookup/no_match") do
        invalid_address = ["88 St", "San Francisco", "CA", "94107"]

        result = @taxamo_client.address_lookup(*invalid_address)
        assert result.no_match?
      end
    end


    test "returns an error result when wrong token is provided" do
      invalid_taxamo_client = Taxamo::Client.new(private_token: "i-am-not-the-right-token")
      VCR.use_cassette("taxamo/address_lookup/invalid_token") do
        github_hq = ["88 Colin P Kelly Jr St", "San Francisco", "CA", "94107-2008"]

        result = invalid_taxamo_client.address_lookup(*github_hq)
        assert result.error.present?
      end
    end

    test "returns no match with a validation error response from taxamo" do
      Failbot.reports.clear

      VCR.use_cassette("taxamo/address_lookup/bad_request") do
        # Postal code does not match region, city or street
        invalid_address = ["62894 Quigley Alley", "Nealfort", "AK", "01496-8811"]

        assert_logged("gh.billing.taxamo.error_code": "validation_error") do
          result = @taxamo_client.address_lookup(*invalid_address)
          assert result.no_match?
          assert result.error.present?
        end

        assert_dogstats_increment(1,
          "billing.taxamo.error",
          tags: [
            "error_code:validation_error",
            "status:400",
          ]
        )
        assert_empty Failbot.reports
      end
    end
  end
end
