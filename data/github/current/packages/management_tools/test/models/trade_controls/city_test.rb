# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsCityTest < GitHub::TestCase
  setup do
    @country_with_city = TradeControls::City.new(
      name: "Ukraine", alpha2: "UA", alpha3: "UKR", domain: "ma",
      region: { name: "Donetsk Oblast", code: 14 }, city: "Makiivka")
    @country_with_another_city = TradeControls::City.new(
      name: "Ukraine", alpha2: "UA", alpha3: "UKR", domain: "am",
      region: { name: "Donetsk Oblast", code: 14 }, city: "Amvrosiyivka")
  end

  test "has basic properties" do
    assert_equal "Ukraine", @country_with_city.name
    assert_equal "UA", @country_with_city.alpha2
    assert_equal "UKR", @country_with_city.alpha3
    assert_equal "ma", @country_with_city.domain
    assert_equal "Makiivka", @country_with_city.city
  end

  test "normalizes some properties" do
    assert_equal "UA", @country_with_another_city.alpha2
    assert_equal "UKR", @country_with_another_city.alpha3
    assert_equal "am", @country_with_another_city.domain
    assert_equal "Amvrosiyivka", @country_with_another_city.city
    assert_equal "14", @country_with_another_city.region_code
    assert_equal "Donetsk Oblast", @country_with_another_city.region_name
  end

  context "equality" do
    test ".eql? is stricter equality based on country code, region, and city" do
      refute @country_with_city.eql? @country_with_another_city
      assert @country_with_city.eql? @country_with_city
    end
  end

  test "can be created from a location" do
    makiivka = TradeControls::City.from_location(country_code: "ua", city: "Makiivka", region_name: "Donetsk Oblast", region_code: 14)
    assert_equal TradeControls::Cities::UA_14_MAKIIVKA, makiivka
  end
end
