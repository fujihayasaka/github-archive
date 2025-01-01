# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationListingLanguageNameTest < GitHub::TestCase

  fixtures do
    @integration_listing = create :integration_listing
    @language_name = create(:language_name)
  end

  test "an integration listing can have many languages" do
    refute @integration_listing.languages.include?(@language_name)
    @integration_listing.languages << @language_name
    assert @integration_listing.languages.include?(@language_name)
  end

  test "a language can have many integration listings" do
    refute @language_name.integration_listings.include?(@integration_listing)
    @language_name.integration_listings << @integration_listing
    assert @language_name.integration_listings.include?(@integration_listing)
  end
end
