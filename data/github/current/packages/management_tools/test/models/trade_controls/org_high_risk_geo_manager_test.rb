# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControlsOrgHighRiskGeoManagerTest < GitHub::TestCase
  def self.exposes_consistent_interface(subject)
    test "responds to high_risk_geo" do
      assert subject.respond_to? :high_risk_geo
    end
  end

  context "#high_risk_geo" do
    test "returns the country code for high risk email domains" do
      geo_manager = TradeControls::OrgHighRiskGeoManager.new(email: "test@example.ir")
      assert_equal geo_manager.high_risk_geo, "IRN"
    end

    test "does not return the country code for non-risk email domains" do
      geo_manager = TradeControls::OrgHighRiskGeoManager.new(email: "test@example.uk")
      assert_nil geo_manager.high_risk_geo
    end

    test "returns the country code for high risk website tlds" do
      geo_manager = TradeControls::OrgHighRiskGeoManager.new(website_url: "my-blog.ir")

      assert_equal geo_manager.high_risk_geo, "IRN"
    end

    test "does not return the country code for non-risk website tlds" do
      geo_manager = TradeControls::OrgHighRiskGeoManager.new(website_url: "my-blog.uk")

      assert_nil geo_manager.high_risk_geo
    end
  end
end
