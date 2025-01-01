# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesVscsServiceStampTest < GitHub::TestCase
  skip_enterprise

  BOSTON = {
    name: "Boston",
    location: { latitude: 42.358056, longitude: -71.063611 },
    nearest: "EastUs",
  }

  fixtures do
    @user = create(:user)
    emu = create(:emu)
    @business = emu.enterprise_managed_business
  end

  setup do
    # Ensure all stamps are default-enabled
    Codespaces::VscsServiceStamp.public.each do |stamp|
      disable_feature_flag("codespaces_region_override_rejection_#{stamp.region.id.downcase}")
      target_suffix = stamp.vscs_target == :production ? "" : "_#{stamp.vscs_target}"
      disable_feature_flag("codespaces_region_rejecting_creates_#{stamp.region.id.downcase}#{target_suffix}")
      disable_feature_flag("codespaces_region_rejecting_resumes_#{stamp.region.id.downcase}#{target_suffix}")
    end
  end

  context "public" do
    test "stamps are implicitly restricted and filtered by Proxima settings" do
      eu_stamps = %w(westeurope-production westeurope-latestprod)
      GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

      on_multi_tenant_enterprise(tenant: @business) do
        assert_equal eu_stamps.sort, Codespaces::VscsServiceStamp.public.map(&:id).sort
      end
    end
  end

  context "where" do
    test "basic argument permutations work properly" do
      stamp = Codespaces::VscsServiceStamp.public.first
      assert_includes Codespaces::VscsServiceStamp.where, stamp
      assert_includes Codespaces::VscsServiceStamp.where(geo: stamp.geo), stamp
      assert_includes Codespaces::VscsServiceStamp.where(region: stamp.region), stamp
      assert_includes Codespaces::VscsServiceStamp.where(vscs_target: stamp.vscs_target), stamp
    end

    test "geo supports string" do
      stamp = Codespaces::VscsServiceStamp.public.first
      assert_includes Codespaces::VscsServiceStamp.where(geo: stamp.geo.id), stamp
    end

    test "region supports string" do
      stamp = Codespaces::VscsServiceStamp.public.first
      assert_includes Codespaces::VscsServiceStamp.where(region: stamp.region.id), stamp
    end

    test "vscs_target supports strings" do
      stamp = Codespaces::VscsServiceStamp.public.first
      assert_includes Codespaces::VscsServiceStamp.where(vscs_target: stamp.vscs_target.to_s), stamp
    end

    test "prebuilds_available" do
      stamp = Codespaces::VscsServiceStamp.public.first
      stamp.expects(:prebuilds_available).at_least_once.returns(true)
      assert_includes Codespaces::VscsServiceStamp.where(prebuilds_available: true), stamp
      stamp.expects(:prebuilds_available).at_least_once.returns(false)
      refute_includes Codespaces::VscsServiceStamp.where(prebuilds_available: true), stamp
    end

    test "available_to leverages available?" do
      stamp = Codespaces::VscsServiceStamp.public.first
      stamp.expects(:available?).with(user: @user).returns(true)
      assert_includes Codespaces::VscsServiceStamp.where(available_to: @user), stamp
      stamp.expects(:available?).with(user: @user).returns(false)
      refute_includes Codespaces::VscsServiceStamp.where(available_to: @user), stamp
    end

    test "available_for_creates_to leverages availabe_for_creates?" do
      stamp = Codespaces::VscsServiceStamp.public.first
      stamp.expects(:available_for_creates?).with(user: @user).returns(true)
      assert_includes Codespaces::VscsServiceStamp.where(available_for_creates_to: @user), stamp
      stamp.expects(:available_for_creates?).with(user: @user).returns(false)
      refute_includes Codespaces::VscsServiceStamp.where(available_for_creates_to: @user), stamp
    end

    test "returns none when 'no geos' explicitly specified" do
      assert_empty Codespaces::VscsServiceStamp.where(geo: [])
    end
  end

  context "find" do
    test "finds a stamp given a region and target" do
      assert Codespaces::VscsServiceStamp.find(region: "UkSouth", vscs_target: :production)
    end

    test "fails to find stamps when restricted by Proxima" do
      GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")
      refute Codespaces::VscsServiceStamp.find(region: "UkSouth", vscs_target: :production)
    end
  end

  context "closest_available" do
    test "finds the closest available stamp for a user" do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])
      expected = Codespaces::VscsServiceStamp.find(region: BOSTON[:nearest], vscs_target: :production)
      assert_equal expected.id, Codespaces::VscsServiceStamp.closest_available(user: @user, vscs_target: :production, client_ip: "1.2.3.4").id
    end

    test "still returns a stamp when geolocation fails" do
      assert Codespaces::VscsServiceStamp.closest_available(user: @user, vscs_target: :production, client_ip: "1.2.3.4")
    end

    test "respects Proxima restrictions" do
      GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")
      GitHub.context.push(actor_ip: "1.2.3.4")
      # Sorry but Boston/EastUs is not available in this Proxima stamp...
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])

      on_multi_tenant_enterprise(tenant: @business) do
        assert_equal "westeurope-production", Codespaces::VscsServiceStamp.closest_available(user: @user, vscs_target: :production, client_ip: "1.2.3.4").id
      end
    end

    test "uses the next closest stamp when the closest one is failed over" do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])
      # Ruh-roh EastUs is failed over, but EastUs2 is still available
      enable_feature_flag("codespaces_region_rejecting_creates_eastus")
      assert_equal "eastus2-production", Codespaces::VscsServiceStamp.closest_available(user: @user, vscs_target: :production, client_ip: "1.2.3.4").id
    end
  end

  context "available_for_prebuilds" do
    test "supports codespaces_prebuilds_new_regions by ignoring prebuild_availability completely" do
      stamp = Codespaces::VscsServiceStamp.public.first
      stamp.expects(:prebuilds_available).at_least_once.returns(false)
      repository = create(:repository)
      disable_feature_flag(:codespaces_prebuilds_new_regions)
      refute_includes Codespaces::VscsServiceStamp.available_for_prebuilds(repository: repository), stamp
      enable_feature_flag(:codespaces_prebuilds_new_regions, repository)
      assert_includes Codespaces::VscsServiceStamp.available_for_prebuilds(repository: repository), stamp
    end

    test "can be called without a repository which ignores the codespaces_prebuilds_new_regions flag" do
      stamp = Codespaces::VscsServiceStamp.public.first
      stamp.expects(:prebuilds_available).at_least_once.returns(false)
      disable_feature_flag(:codespaces_prebuilds_new_regions)
      refute_includes Codespaces::VscsServiceStamp.available_for_prebuilds, stamp
      enable_feature_flag(:codespaces_prebuilds_new_regions)
      refute_includes Codespaces::VscsServiceStamp.available_for_prebuilds, stamp
    end
  end

  context "available_backups" do
    test "returns all other stamps in the same geo/target that are available to the user by default" do
      stamp = Codespaces::VscsServiceStamp.find(region: "SouthEastAsia", vscs_target: :production)
      other_asse_stamps = Codespaces::VscsServiceStamp.where(geo: "SoutheastAsia", vscs_target: :production).without(stamp)

      assert_equal other_asse_stamps.sort, stamp.available_backups(user: @user).sort
    end

    test "will return backups in other geos if literally the entire geo is failed over in non-prod targets" do
      enable_feature_flag(:codespaces_developer, @user)
      stamp = Codespaces::VscsServiceStamp.find(region: "CanadaCentral", vscs_target: :ppe)
      stamp.geo.stamps.each do |stamp|
        enable_feature_flag("codespaces_region_rejecting_creates_#{stamp.region.id.downcase}")
      end

      assert stamp.available_backups(user: @user).present?
    end

    test "respects Proxima" do
      GitHub.stubs(:codespaces_stamp_azure_geo).returns("apac")
      stamp = Codespaces::VscsServiceStamp.find(region: "SouthEastAsia", vscs_target: :production)
      stamp.geo.stamps.each do |stamp|
        enable_feature_flag("codespaces_region_rejecting_creates_#{stamp.region.id.downcase}")
      end

      on_multi_tenant_enterprise(tenant: @business) do
        refute stamp.available_backups(user: @user).present?
      end
    end
  end

  context "backup" do
    test "it returns the only available backup when there is only one" do
      stamp = Codespaces::VscsServiceStamp.public.first
      other_stamp = Codespaces::VscsServiceStamp.public.second
      stamp.stubs(:available_backups).returns([other_stamp])

      assert_equal other_stamp, stamp.backup(user: @user)
    end

    test "it returns the closest of its available_backups in the same geo" do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])
      enable_feature_flag("codespaces_region_rejecting_creates_eastus")
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)

      assert_equal "eastus2-production", stamp.backup(user: @user).id
    end

    test "it returns nothing when the entire geo is failed over in production with codespaces_geoconstrained_backups enabled" do
      enable_feature_flag(:codespaces_geoconstrained_backups, @user)
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)
      stamp.geo.stamps.each do |stamp|
        enable_feature_flag("codespaces_region_rejecting_creates_#{stamp.region.id.downcase}")
      end

      refute stamp.backup(user: @user, client_ip: "1.2.3.4")
    end

    test "it returns the closest available backup even if the entire geo is failed over" do
      disable_feature_flag(:codespaces_geoconstrained_backups)
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)
      stamp.geo.stamps.each do |stamp|
        enable_feature_flag("codespaces_region_rejecting_creates_#{stamp.region.id.downcase}")
      end

      assert_equal "westus3-production", stamp.backup(user: @user, client_ip: "1.2.3.4").id
    end

    test "it returns the closest available backup to the stamp itself even if the entire geo is failed over when IP geolocation fails" do
      disable_feature_flag(:codespaces_geoconstrained_backups)
      Codespaces::Locations::RegionLocator.any_instance.stubs(:from_ip_location_lookup).returns(nil)
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)
      stamp.geo.stamps.each do |stamp|
        enable_feature_flag("codespaces_region_rejecting_creates_#{stamp.region.id.downcase}")
      end

      assert_equal "westus3-production", stamp.backup(user: @user, client_ip: "1.2.3.4").id
    end
  end

  context "api_url" do
    test "given a known location" do
      api_url = Codespaces::VscsServiceStamp.find(region: "WestUs2", vscs_target: :production).api_url
      assert_equal "https://westus2.online.visualstudio.com", api_url
    end

    test "given a development target" do
      api_url = Codespaces::VscsServiceStamp.find(region: "WestUs2", vscs_target: :development).api_url
      assert_equal "https://westus2-ci-online.dev.core.vsengsaas.visualstudio.com", api_url
    end

    test "uses the default url when the API call fails" do
      Codespaces::AnonymousVscsClient.any_instance.expects(:get).with("api/v1/locations").raises(Codespaces::VscsClient::TimeoutError)
      api_url = Codespaces::VscsServiceStamp.find(region: "WestUs2", vscs_target: :development).api_url
      assert_equal "https://online.dev.core.vsengsaas.visualstudio.com", api_url
    end
  end
end
