# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationListingFeatureTest < GitHub::TestCase

  fixtures do
    @integration_listing = create :integration_listing
    @integration_feature = create :integration_feature
  end

  test "an integration listing can have many features" do
    assert_equal 0, @integration_listing.features.count
    @integration_listing.features << @integration_feature
    assert @integration_listing.features.include?(@integration_feature)
  end

  test "an integration feature can have many listings" do
    assert_equal 0, @integration_feature.listings.count
    @integration_feature.listings << @integration_listing
    assert @integration_feature.listings.include?(@integration_listing)
  end

end
