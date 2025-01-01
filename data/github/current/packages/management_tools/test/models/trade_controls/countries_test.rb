# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsCountriesTest < GitHub::TestCase
  setup do
    @country_a = TradeControls::Country.new(
      name: "A Country", alpha2: "AA", alpha3: "AAA", domain: "aa")
    @country_b = TradeControls::Country.new(
      name: "B Country", alpha2: "BB", alpha3: "BBB", domain: "bb")
    @country_c = TradeControls::Country.new(
      name: "C Country", alpha2: "CC", alpha3: "CCC", domain: "cc")

    @countries = TradeControls::Countries.new([
      @country_a, @country_b, @country_c])
  end

  context "BILLING_ADDRESS_DENYLIST" do
    test "includes the right countries' alpha3 codes" do
      countries = TradeControls::Countries::BILLING_ADDRESS_DENYLIST
      assert_equal %w[CUB PRK SYR], countries.alpha3
    end
  end

  context ".currently_unsanctioned" do
    [
      %w[CU CUB],
      %w[KP PRK],
      %w[SY SYR],
    ].each do |(code2, code3)|
      test "#{code2} OR #{code3} does not show up in the list" do
        alpha2, alpha3 = TradeControls::Countries.currently_unsanctioned
          .map { |(_, c2, c3, _)| [c2, c3] }.transpose

        assert_equal 2, T.must(T.must(alpha2).first).length
        assert_equal 3, T.must(T.must(alpha3).first).length

        refute T.must(alpha2).include?(code2)
        refute T.must(alpha3).include?(code3)

        # Ensure we're getting some data left
        assert T.must(alpha2).include?("US")
        assert T.must(alpha3).include?("USA")
      end
    end
  end

  test "it is enumerable" do
    country1 = TradeControls::Country.new(name: "1")
    country2 = TradeControls::Country.new(name: "2")
    country3 = TradeControls::Country.new(name: "3")
    list = TradeControls::Countries.new([country1, country2, country3])

    assert_equal 3, list.count
    assert_equal [country1, country2, country3], list.to_a
  end

  test "it does not allow duplicates" do
    country1 = TradeControls::Country.new(name: "1")
    country2 = TradeControls::Country.new(name: "2")
    country3 = TradeControls::Country.new(name: "3")
    country4 = TradeControls::Country.new(name: "4")
    list = TradeControls::Countries.new([country1, country2, country2, country3, country4, country3])

    assert_equal 4, list.count
    assert_equal [country1, country2, country3, country4], list.to_a
  end

  context "#where / #find_by" do
    test "matches on a single attribute" do
      conditions = { name: @country_a.name }

      assert_same @country_a, @countries.find_by(**conditions)
      assert_equal [@country_a], @countries.where(**conditions)
    end

    test "matches on multiple attributes" do
      conditions = { alpha2: @country_b.alpha2, alpha3: @country_b.alpha3 }

      assert_same @country_b, @countries.find_by(**conditions)
      assert_equal [@country_b], @countries.where(**conditions)
    end

    test "matches on an array of possible values" do
      conditions = { alpha2: %w[BB CC] }

      assert_same @country_b, @countries.find_by(**conditions)
      assert_equal [@country_b, @country_c], @countries.where(**conditions)
    end
  end

  context ".marketing_targeted_countries" do
    test "excludes sanctioned countries" do
      sanctioned = TradeControls::Countries::BILLING_ADDRESS_DENYLIST.alpha3

      sanctioned.each do |c|
        refute TradeControls::Countries.marketing_targeted_countries.include?(c)
      end
    end

    test "excludes marketing block-list countries" do
      blocked = TradeControls::Countries::MARKETING_BLOCKED_COUNTRY_LIST.alpha3

      blocked.each do |c|
        refute TradeControls::Countries.marketing_targeted_countries.include?(c)
      end
    end

    test "includes other countries" do
      refute TradeControls::Countries.marketing_targeted_countries.empty?
    end
  end

  context ".marketing_targeted_country?" do
    test "returns true for country in marketing_targeted_countries" do
      assert TradeControls::Countries.marketing_targeted_country?("US")
    end

    test "returns false for country not in marketing_targeted_countries" do
      refute TradeControls::Countries.marketing_targeted_country?("KP")
    end

    test "returns false when passed a nil value" do
      refute TradeControls::Countries.marketing_targeted_country?(nil)
    end
  end
end
