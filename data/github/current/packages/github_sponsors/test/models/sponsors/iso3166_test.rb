# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::ISO3166Test < GitHub::TestCase
  test "countries are ordered by name" do
    country_code, country_name = Sponsors::ISO3166.countries.first

    assert_equal "AF", country_code
    assert_equal "Afghanistan", country_name
  end

  test "subdivisions are ordered by name" do
    subdivision_code, subdivision_name = Sponsors::ISO3166.subdivisions(country_code: "AG").first

    assert_equal "AG-10", subdivision_code
    assert_equal "Barbuda", subdivision_name
  end

  test "empty subdivisions hash for invalid country code" do
    assert_equal({}, Sponsors::ISO3166.subdivisions(country_code: "does-not-exist"))
  end

  test "does not hit disk after first loading of country data" do
    # This may or may not be already loaded depending on test ordering, but we make sure it's loaded here!
    Sponsors::ISO3166.countries

    File.expects(:open).never

    Sponsors::ISO3166.countries
  end
end
