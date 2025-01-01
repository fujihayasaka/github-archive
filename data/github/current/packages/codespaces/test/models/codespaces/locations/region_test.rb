# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces::Locations
  class RegionTest < GitHub::TestCase
    include DogstatsTestHelpers

    fixtures do
      @user = create(:user)
      @repo = create(:repository, owner: @user)
      GitHub.flipper[:codespaces_prebuilds_new_regions].disable

      unless GitHub.enterprise?
        emu = create(:emu)
        @business = emu.enterprise_managed_business
      end

      make_trusted_oauth_apps_owner
      @integration = create(:codespaces_integration)
    end

    context "public" do
      test "respects proxima configuration", skip_enterprise: true do
        eu_regions = %w(WestEurope)
        GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

        on_multi_tenant_enterprise(tenant: @business) do
          assert_equal eu_regions, Codespaces::Locations::Region.public.map(&:id)
        end
      end

      test "returns all regions when proxima is not configured but neither is codespaces to prevent enterprise build failures at startup" do
        GitHub.stubs(:codespaces_stamp_azure_geo).returns(nil)
        GitHub.stubs(:codespaces_enabled?).returns(false)

        assert Codespaces::Locations::Region.public
      end
    end

    context "where" do
      test "finds all regions in a geo by name" do
        geo = "UsEast"
        assert_equal %w(CanadaCentral EastUs EastUs2).sort, Codespaces::Locations::Region.where(geo: geo).map(&:id).sort
      end

      test "finds all regions in a geo given an instance of a Geo" do
        geo = Codespaces::Locations::Geo.find("UsEast")
        assert_equal %w(CanadaCentral EastUs EastUs2).sort, Codespaces::Locations::Region.where(geo: geo).map(&:id).sort
      end

      test "fails to find regions in the wrong geo when restricted by proxima" do
        GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

        on_multi_tenant_enterprise(tenant: @business) do
          assert Codespaces::Locations::Region.where(geo: "UsEast").empty?
        end
      end

      test "can find only regions available to a user" do
        # Disable creates in EastUs2
        region = Codespaces::Locations::Region.find("EastUs2")
        region.stamps.each do |stamp|
          target_suffix = stamp.vscs_target == :production ? "" : "_#{stamp.vscs_target}"
          GitHub.flipper["codespaces_region_rejecting_creates_#{stamp.region.id.downcase}#{target_suffix}"].enable
        end
        assert_equal %w(EastUs), Codespaces::Locations::Region.where(geo: "UsEast", available_to: @user).map(&:id)
      end

      test "can find regions with service stamps available in a specific target environment" do
        assert_equal %w(SouthEastAsia CanadaCentral).sort, Codespaces::Locations::Region.where(vscs_target: :ppe).map(&:id).sort
      end

      test "ignores blank vscs_target" do
        assert_equal Codespaces::Locations::Region.public.map(&:id).sort, Codespaces::Locations::Region.where(vscs_target: "").map(&:id).sort
      end

      test "returns none when 'no IDs' explicitly specified" do
        assert_empty Codespaces::Locations::Region.where(id: [])
      end
    end

    context "find" do
      test "finds a region when provided its identifier" do
        assert Codespaces::Locations::Region.find("EastUs")
      end

      test "fails to find a region when restricted by proxima" do
        GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

        on_multi_tenant_enterprise(tenant: @business) do
          refute Codespaces::Locations::Region.find("EastUs")
        end
      end
    end

    context "geo" do
      test "returns the geo associated with the region" do
        assert_equal Codespaces::Locations::Geo.find("UsEast"), Codespaces::Locations::Region.find("EastUs").geo
      end
    end

    context "geo rollout" do
      test "returns the previous geo if the rollout feature flag is declared but not enabled" do
        rollout_feature_flag = :codespaces_geo_rollout_eastus
        GitHub.flipper[rollout_feature_flag].disable
        geo = Codespaces::Locations::Geo.find("UsEast")
        geo.stubs(:rollout_feature_flag).returns(rollout_feature_flag)
        geo.stubs(:previous_geo_id).returns("UsWest")
        assert_equal Codespaces::Locations::Geo.find(geo.previous_geo_id), Codespaces::Locations::Region.find("EastUs").geo
      end

      test "raises if a rollout FF is declared and disabled but no previous geo is configured" do
        rollout_feature_flag = :codespaces_geo_rollout_eastus
        GitHub.flipper[rollout_feature_flag].disable
        geo = Codespaces::Locations::Geo.find("UsEast")
        geo.stubs(:rollout_feature_flag).returns(rollout_feature_flag)
        geo.stubs(:previous_geo_id).returns(nil)
        assert_raises RuntimeError do
          Codespaces::Locations::Region.find("EastUs").geo
        end
      end
    end
  end
end
