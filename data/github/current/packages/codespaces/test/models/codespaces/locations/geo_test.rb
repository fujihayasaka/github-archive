# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces::Locations
  class GeoTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @user = create(:user)

      unless GitHub.enterprise?
        emu = create(:emu)
        @business = emu.enterprise_managed_business
      end
    end

    setup do
      # Disable all geos that are under FF by default
      Codespaces::Locations::Geo.public.each do |geo|
        next unless geo.rollout_feature_flag

        GitHub.flipper[geo.rollout_feature_flag].disable
      end
      @all_geos = Codespaces::Locations::Geo.public.map(&:id).sort
    end


    context "where" do
      test "returns all geos for default target" do
        assert_equal @all_geos.sort, Codespaces::Locations::Geo.where(vscs_target: Codespaces::Vscs.default_target).map(&:id).sort
      end

      test "returns limited geos for non-prod target" do
        ppe_geos = %w(UsEast SoutheastAsia)
        assert_equal ppe_geos.sort, Codespaces::Locations::Geo.where(vscs_target: :ppe).map(&:id).sort
      end

      test "returns limited geos for proxima", skip_enterprise: true do
        eu_geos = %w(EuropeWest)
        GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

        on_multi_tenant_enterprise(tenant: @business) do
          assert_equal eu_geos, Codespaces::Locations::Geo.where(vscs_target: Codespaces::Vscs.default_target).map(&:id)
          assert_equal [], Codespaces::Locations::Geo.where(vscs_target: :ppe).to_a
        end
      end

      test "available to user" do
        # Disable all stamps in UsEast
        target_suffix = Codespaces::Vscs.default_target == :production ? "" : "_#{Codespaces::Vscs.default_target}"
        Codespaces::Locations::Geo.find("UsEast").stamps.each do |stamp|
          GitHub.flipper["codespaces_region_rejecting_creates_#{stamp.region.id.downcase}#{target_suffix}"].enable
        end
        expected_geos = @all_geos - %w(UsEast)
        assert_equal expected_geos.sort, Codespaces::Locations::Geo.where(vscs_target: Codespaces::Vscs.default_target, available_to: @user).map(&:id).sort
      end

      test "primary region exists" do
        geos = Codespaces::Locations::Geo.where(primary_region: "WestEurope")
        assert_equal 1, geos.count
        assert_equal "EuropeWest", geos.first.id
      end

      test "primary region does not exist" do
        assert Codespaces::Locations::Geo.where(primary_region: "FakeRegion").empty?
      end

      test "returns none when 'no IDs' explicitly specified" do
        assert_empty Codespaces::Locations::Geo.where(id: [])
      end
    end

    context "regions" do
      test "returns the regions within the geo" do
        geo = Codespaces::Locations::Geo.find("UsEast")
        assert_equal %w(CanadaCentral EastUs EastUs2).sort, geo.regions.map(&:id).sort
      end
    end

    context "available_regions" do
      test "only returns regions that have available stamps" do
        region = Codespaces::Locations::Region.find("EastUs")
        region.stamps.each do |stamp|
          target_suffix = stamp.vscs_target == :production ? "" : "_#{stamp.vscs_target}"
          GitHub.flipper["codespaces_region_rejecting_creates_#{stamp.region.id.downcase}#{target_suffix}"].enable
        end
        geo = Codespaces::Locations::Geo.find("UsEast")
        assert_equal [Codespaces::Locations::Region.find("EastUs2")], geo.available_regions(user: @user).to_a
      end
    end

    context "geo rollouts" do
      test "hides geos that are not enabled" do
        rollout_feature_flag = :codespaces_geo_rollout_eastus
        geo = Codespaces::Locations::Geo.find("UsEast")
        geo.stubs(:rollout_feature_flag).returns(rollout_feature_flag)
        geo.stubs(:previous_geo_id).returns("UsWest")

        # UsEast rollout is enabled...
        GitHub.flipper[rollout_feature_flag].enable

        assert Codespaces::Locations::Geo.find("UsEast")

        # UsEast rollout is disabled...
        GitHub.flipper[rollout_feature_flag].disable

        refute Codespaces::Locations::Geo.find("UsEast")
      end
    end

    context "stamps" do
      test "returns all stamps for the geo" do
        expected_stamps = %w(uksouth-latestprod uksouth-production westeurope-latestprod westeurope-production)
        geo = Codespaces::Locations::Geo.find("EuropeWest")
        assert_equal expected_stamps, geo.stamps.map(&:id).sort
      end
    end
  end
end
