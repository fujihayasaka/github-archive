# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsUserHighRiskGeoManagerTest < GitHub::TestCase
  def self.exposes_consistent_interface(subject)
    test "responds to high_risk_geo" do
      assert subject.respond_to? :high_risk_geo
    end
  end

  context "#high_risk_geo" do
    test "returns the country code for high risk email domains" do
      geo_manager = TradeControls::UserHighRiskGeoManager.new(email: "test@example.ir")
      assert_equal geo_manager.high_risk_geo, "IRN"
    end

    test "does not return the country code for non-risk email domains" do
      geo_manager = TradeControls::UserHighRiskGeoManager.new(email: "test@example.uk")
      assert_nil geo_manager.high_risk_geo
    end

    test "returns the country code for high risk IPs" do
      location = {
        country_code: "IR"
      }
      geo_manager = TradeControls::UserHighRiskGeoManager.new(location: location)

      assert_equal geo_manager.high_risk_geo, "IRN"
    end

    test "returns the country code for high risk IPs of Belarus" do
      location = {
        country_code: "BY"
      }
      geo_manager = TradeControls::UserHighRiskGeoManager.new(location: location)

      assert_equal geo_manager.high_risk_geo, "BLR"
    end

    test "returns the country code and region for high risk Crimea region" do
      location = {
        country_code: "UA",
        region_name: "Crimea"
      }

      geo_manager = TradeControls::UserHighRiskGeoManager.new(location: location)

      assert_equal geo_manager.high_risk_geo, "UKR -- Crimea"
    end

    test "returns the country code and region for high risk Luhansk region" do
      location = {
        country_code: "UA",
        region_name: "Luhansk"
      }
      geo_manager = TradeControls::UserHighRiskGeoManager.new(location: location)

      assert_equal geo_manager.high_risk_geo, "UKR -- LNR"
    end

    test "returns the country code and region for high risk Donetsk Oblast region" do
      location = {
        country_code: "UA",
        region_name: "Donetsk Oblast"
      }

      geo_manager = TradeControls::UserHighRiskGeoManager.new(location: location)
      assert_equal geo_manager.high_risk_geo, "UKR -- DNR"
    end

    test "does not return the country code for non-risk IPs" do
      location = {
        country_code: "UK"
      }
      geo_manager = TradeControls::UserHighRiskGeoManager.new(location: location)

      assert_nil geo_manager.high_risk_geo
    end
  end
end
