# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsCountryTest < GitHub::TestCase
  setup do
    @country_a_no_region = TradeControls::Country.new(
      name: "A country", alpha2: "AC", alpha3: "ACC", domain: "ac")
    @country_a_with_region = TradeControls::Country.new(
      name: "A country", alpha2: "AC", alpha3: "ACC", domain: "ac",
      region: { name: "a region", code: 42 })
    @country_b_region_x = TradeControls::Country.new(
      name: "B country", alpha2: "BC", alpha3: "BCC", domain: "bc",
      region: { name: "region x", code: 7 })
    @country_b_region_y = TradeControls::Country.new(
      name: "B country", alpha2: "BC", alpha3: "BCC", domain: "bc",
      region: { name: "region y", code: 9 })
  end

  test "has basic properties" do
    country = TradeControls::Country.new(
      name: "My country", alpha2: "MY", alpha3: "MYC", domain: "mc")
    assert_equal "My country", country.name
    assert_equal "MY", country.alpha2
    assert_equal "MYC", country.alpha3
    assert_equal "mc", country.domain
  end

  test "has optional region" do
    without_region = TradeControls::Country.new(
      name: "My country", alpha2: "MY", alpha3: "MYC", domain: "mc")

    refute_predicate without_region, :region?

    country = TradeControls::Country.new(
      name: "My country", alpha2: "MY", alpha3: "MYC", domain: "mc",
      region: { name: "a region", code: "42" })

    assert_predicate country, :region?
    assert_equal "a region", country.region_name
    assert_equal "42", country.region_code
    assert_equal "MY-42", country.subdivision_code
  end

  test "normalizes some properties" do
    country = TradeControls::Country.new(
      name: "My country", alpha2: "My", alpha3: "Myc", domain: "Mc",
      region: { name: "a region", code: 42 })

    assert_equal "MY", country.alpha2
    assert_equal "MYC", country.alpha3
    assert_equal "mc", country.domain
    assert_equal "42", country.region_code
  end

  context "equality" do
    test "<=> determines sortability by country+region code" do
      sorted = [
        @country_b_region_y,
        @country_a_with_region,
        @country_a_no_region,
        @country_b_region_x,
      ].sort!

      # Sorts by country code first, then by region code (if set)
      assert_same @country_a_no_region, sorted[0]
      assert_same @country_a_with_region, sorted[1]
      assert_same @country_b_region_x, sorted[2]
      assert_same @country_b_region_y, sorted[3]
    end

    test "== is loose equality based only on 2 digit character code, not region" do
      assert_equal @country_a_no_region, @country_a_with_region
      assert_equal @country_b_region_x, @country_b_region_y

      refute_equal @country_b_region_x, @country_a_no_region
      refute_equal @country_b_region_x, @country_a_with_region
    end

    test ".eql? is stricter equality based on 2 digit character code and region" do
      refute @country_a_no_region.eql? @country_a_with_region
      refute @country_b_region_x.eql? @country_b_region_y
      refute @country_b_region_x.eql? @country_a_no_region
      refute @country_b_region_x.eql? @country_a_with_region

      # Variables named here to indicate the properties:
      # {country code c or x}{region name r or x (_ is nil)}{region code 1 or 0 (_ is nil)}

      cr_ = TradeControls::Country.new(alpha2: "CC", region: { name: "R" })
      cr1 = TradeControls::Country.new(alpha2: "CC", region: { name: "R", code: 1 })
      c_1 = TradeControls::Country.new(alpha2: "CC", region: { code: 1 })

      xr1 = TradeControls::Country.new(alpha2: "XX", region: { name: "R", code: 1 })
      cx1 = TradeControls::Country.new(alpha2: "CC", region: { name: "X", code: 1 })
      cr0 = TradeControls::Country.new(alpha2: "CC", region: { name: "R", code: 0 })

      assert cr1.eql?(cr_), "same country code, same region name, one region code nil"
      assert cr1.eql?(c_1), "same country code, same region code, one region name nil"
      assert cr1.eql?(cx1), "same country code, same region code, different region name"
      assert cr1.eql?(cr0), "same country code, same region name, different region code"
      refute cr1.eql?(xr1), "different country code, same region name and code"
      refute cr_.eql?(c_1), "same country code, one region name nil, other region code nil"
    end
  end

  test "can be created from a braintree country" do
    cuba_info = Braintree::Address::CountryNames.find { |c| c[1] == "CU" }
    cuba = TradeControls::Country.from_braintree(cuba_info)
    assert_equal TradeControls::Countries::CUBA, cuba
  end

  test "can be created from a location" do
    north_korea = TradeControls::Country.from_location(country_code: "kp")
    assert_equal TradeControls::Countries::NORTH_KOREA, north_korea
  end

  test "can be created from an ip" do
    GitHub::Location.expects(:look_up).with("some ip").returns(country_code: "SY")
    syria = TradeControls::Country.from_ip("some ip")
    assert_equal TradeControls::Countries::SYRIA, syria
  end

  test "can be created from a domain" do
    syria = TradeControls::Country.from_domain("sy")
    assert_equal TradeControls::Countries::SYRIA, syria
  end
end
