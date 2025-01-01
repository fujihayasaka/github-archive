# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/codespaces_network_configuration_helpers"

class Codespaces::GetRegionForUserTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesNetworkConfigurationTestHelper

  NAIROBI = {
    name: "Nairobi",
    location: { latitude: -1.286389, longitude: 36.817222 },
    nearest: "CentralIndia",
  }
  BOSTON = {
    name: "Boston",
    location: { latitude: 42.358056, longitude: -71.063611 },
    nearest: "EastUs",
  }
  RALEIGH = {
    name: "Raleigh",
    location: { latitude: 35.773782, longitude: -78.638205 },
    nearest: "EastUs2",
  }
  MISSOULA = {
    name: "Missoula",
    location: { latitude: 46.8625, longitude: -114.011667 },
    nearest: "WestUs2",
  }
  INDIA = {
    name: "New Delhi",
    location: { latitude: 28.613895, longitude: 77.209006 },
    nearest: "SouthEastAsia",
  }
  LONDON = {
    name: "London",
    location: { latitude: 51.507222, longitude: -0.1275 },
    nearest: "UkSouth",
  }

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
    GitHub.flipper[:codespaces_prebuilds_new_regions].disable
    GitHub.flipper[:codespaces_vnet_injection_beta].disable
    GitHub.flipper[:codespaces_salus_beta_customers].disable

    unless GitHub.enterprise?
      emu = create(:emu)
      @business = emu.enterprise_managed_business
    end
    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)
  end

  context "generic, with no requested or saved location info" do
    test "uses the closest region to the provided client_ip" do
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(LONDON[:location])
      assert_equal "UkSouth", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, client_ip: "1.2.3.4")
    end

    test "falls back on request context IP address if no client_ip is provided" do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(LONDON[:location])
      assert_equal "UkSouth", Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
    end

    test "returns only regions with GA stamps in them to normal users" do
      GitHub.flipper[:codespaces_developer].disable(@user)
      # Only one GA stamp in production
      Codespaces::VscsServiceStamp.where(vscs_target: :production).each { |stamp| stamp.stubs(ga?: false) }
      stamp = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)
      stamp.stubs(ga?: true)
      assert_includes stamp.region.id, Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
    end

    test "throws an error if a normal user attempted to use a non-production vscs_target since that's not allowed" do
      GitHub.flipper[:codespaces_developer].disable(@user)

      assert_raises(Codespaces::Locations::Region::UnavailableError) do
        Codespaces::GetRegionForUser.call(user: @user, repository: @repo, vscs_target: :development)
      end
    end

    test "returns regions regardless of stamp availability to codespaces_developers" do
      GitHub.flipper[:codespaces_developer].enable(@user)
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(LONDON[:location])
      # No GA stamps at all
      Codespaces::VscsServiceStamp.where(vscs_target: :production).each { |stamp| stamp.stubs(ga?: false) }
      assert_includes "UkSouth", Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
    end

    context "proxima", skip_enterprise: true do
      test "uses a region allowed by proxima" do
        GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

        on_multi_tenant_enterprise(tenant: @business) do
          assert_equal "WestEurope", Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
        end
      end
    end

    context "vnet injection", skip_enterprise: true do
      test "with vnet-injection-specified region, that region is used" do
        vnet_injected_region = "EastUs"

        user = create(:user)
        org = setup_vnet_injection_org(admin: user, regions: [vnet_injected_region])
        repo = create(:private_repository, owner: org)

        assert_equal vnet_injected_region, Codespaces::GetRegionForUser.call(user: user, repository: repo)
      end
    end
  end

  context "with a requested_region" do
    test "uses a region within the specified region's geo" do
      region = Codespaces::Locations::Region.find("WestEurope")
      assert_includes region.geo.regions.map(&:id), Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_region: "WestEurope")
    end

    test "uses the closest region to the user within the specified region's geo" do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(LONDON[:location])
      assert_equal "UkSouth", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_region: "WestEurope")
    end

    test "it assigns a backup if the requested region is unavailable" do
      disable_stamp(Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production))

      assert_equal "EastUs2", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_region: "EastUs")
    end

    test "it finds the next best backup if both the primary and backup stamps are unavailable" do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])

      stamp = Codespaces::VscsServiceStamp.find(region: BOSTON[:nearest], vscs_target: :production)
      # Grab its first backup so we can disable it both.
      backup = stamp.backup(user: @user)
      # Pretend all our regions are in the same geo.
      Codespaces::Locations::Region.any_instance.stubs(geo: stamp.geo)

      disable_stamp(stamp)
      disable_stamp(backup)

      assert_equal "WestUs3", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_region: "EastUs")
    end

    test "codespaces_developer are afforded region-granularity via requested_region" do
      GitHub.flipper[:codespaces_developer].enable
      assert_equal "AustraliaEast", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_region: "AustraliaEast")
    end

    test "users without codespaces_developer FF only get geo-granularity by specifying a region" do
      GitHub.flipper[:codespaces_developer].disable
      region = Codespaces::Locations::Region.find("WestEurope")
      assert_includes region.geo.regions.map(&:id), Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_region: "WestEurope")
    end
  end

  context "with a requested_geo", skip_enterprise: true do
    test "raises if passed an invalid geo" do
      assert_raises(Codespaces::Locations::Geo::InvalidError) do
        Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_geo: "FooBar")
      end
    end

    test "IP geolcation assigns correct region" do
      # Boston, so UK South is closer than West Europe
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])

      assert_equal "UkSouth", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_geo: "EuropeWest")
    end

    test "it works with non-prod vscs targets" do
      GitHub.flipper[:codespaces_developer].enable(@user)
      # Nairobi, so CentralIndia is closer than SouthEastAsia, but only SouthEastAsia exists for PPE
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(NAIROBI[:location])

      assert_equal "SouthEastAsia", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_geo: "SoutheastAsia", vscs_target: :ppe)
    end

    test "randomly assigns a geo if IP assignment fails" do
      Codespaces::Locations::RegionLocator.any_instance.stubs(:from_ip_location_lookup).returns(nil)
      assert_includes %w[WestEurope UkSouth], Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_geo: "EuropeWest")
    end

    test "it assigns a backup if the IP assigned region is unavailable" do
      disable_stamp(Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production))
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])

      assert_equal "EastUs2", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_geo: "UsEast")
    end

    test "it finds the next best backup if both the primary and backup stamps are unavailable" do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])

      stamp = Codespaces::VscsServiceStamp.find(region: BOSTON[:nearest], vscs_target: :production)
      # Grab its first backup so we can disable it both.
      backup = stamp.backup(user: @user)
      # Pretend all our regions are in the same geo.
      Codespaces::Locations::Region.any_instance.stubs(geo: stamp.geo)

      disable_stamp(stamp)
      disable_stamp(backup)

      assert_equal "WestUs3", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_geo: "UsEast")
    end

    test "it raises if there are no regions available to the user anywhere with codespaces_geoconstrained_backups disabled" do
      GitHub.flipper[:codespaces_geoconstrained_backups].disable
      Codespaces::VscsServiceStamp.where(vscs_target: :production).each { |stamp| disable_stamp(stamp) }

      assert_raises(Codespaces::Locations::Region::UnavailableError) do
        Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_geo: "UsEast")
      end
    end

    test "it raises if there are no regions available to the user in their requested geo with codespaces_geoconstrained_backups enabled" do
      GitHub.flipper[:codespaces_geoconstrained_backups].enable(@user)
      Codespaces::VscsServiceStamp.where(vscs_target: :production, geo: "UsEast").each { |stamp| disable_stamp(stamp) }

      assert_raises(Codespaces::Locations::Region::UnavailableError) do
        Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_geo: "UsEast")
      end
    end

    test "with vnet-injection-specified region; requested geo is ignored" do
      vnet_injected_region = "EastUs"
      requested_geo = "EuropeWest"

      user = create(:user)
      org = setup_vnet_injection_org(admin: user, regions: [vnet_injected_region])
      repo = create(:private_repository, owner: org)

      assert_equal vnet_injected_region, Codespaces::GetRegionForUser.call(user: user, repository: repo, requested_geo: requested_geo)
    end
  end

  context "with a preferred geo saved for the user", skip_enterprise: true do
    test "uses the closest region to the user within their preferred geo" do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(RALEIGH[:location])
      settings = Codespaces::Settings.for_user(@user)
      settings.default_location = "EastUs"
      settings.save

      assert_equal "EastUs2", Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
    end

    test "it assigns a backup if the preferred region is unavailable" do
      settings = Codespaces::Settings.for_user(@user)
      settings.default_location = "EastUs"
      settings.save

      disable_stamp(Codespaces::VscsServiceStamp.find(region: "EastUs2", vscs_target: :production))

      assert_equal "EastUs", Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
    end

    test "it finds the next best backup if both the primary and backup stamps are unavailable" do
      settings = Codespaces::Settings.for_user(@user)
      settings.default_location = "EastUs"
      settings.save

      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])

      stamp = Codespaces::VscsServiceStamp.find(region: BOSTON[:nearest], vscs_target: :production)
      # Grab its first backup so we can disable it both.
      backup = stamp.backup(user: @user)
      # Pretend all our regions are in the same geo.
      Codespaces::Locations::Region.any_instance.stubs(geo: stamp.geo)

      disable_stamp(stamp)
      disable_stamp(backup)

      assert_equal "WestUs3", Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
    end

    test "with vnet-injection-specified region; default setting is ignored" do
      vnet_injected_region = "EastUs"
      user = create(:user)
      settings = Codespaces::Settings.for_user(user)
      settings.default_location = "WestUs2"
      settings.save

      org = setup_vnet_injection_org(admin: user, regions: [vnet_injected_region])
      repo = create(:private_repository, owner: org)

      assert_equal vnet_injected_region, Codespaces::GetRegionForUser.call(user: user, repository: repo)
    end

    test "it ignores the setting if the chosen target has no service stamps configured for it" do
      GitHub.flipper[:codespaces_developer].enable(@user)
      settings = Codespaces::Settings.for_user(@user)
      settings.default_location = "EastUs"
      settings.save

      assert_includes %w[WestEurope WestUs2], Codespaces::GetRegionForUser.call(user: @user, repository: @repo, vscs_target: :development)
    end

    context "proxima", skip_enterprise: true do
      test "uses a region" do
        # Make it so UkSouth is naturally the closest for the user and would normally be used.
        GitHub.context.push(actor_ip: "1.2.3.4")
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(LONDON[:location])
        GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

        on_multi_tenant_enterprise(tenant: @business) do
          settings = Codespaces::Settings.for_user(@user)
          settings.default_location = "WestEurope"
          settings.save

          # Proxima restriction disallows UkSouth though so we should always get WestEurope
          assert_equal "WestEurope", Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
        end
      end

      test "it ignores the setting if that region is unavailable in the stamp" do
        on_multi_tenant_enterprise(tenant: @business) do
          GitHub.stubs(:codespaces_stamp_azure_geo).returns("apac")
          settings = Codespaces::Settings.for_user(@user)
          settings.default_location = "WestEurope"
          settings.save

          assert_includes %w[SouthEastAsia CentralIndia], Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
        end
      end
    end
  end

  context "for_creation, with IP lookup" do
    test "uses IP lookup if none other specified, and instruments" do
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(NAIROBI[:location])
      assert_equal NAIROBI[:nearest], Codespaces::GetRegionForUser.call(user: @user, repository: @repo, client_ip: "1.2.3.4")
    end

    test "it assigns a backup if the preferred region is unavailable" do
      stamp = Codespaces::VscsServiceStamp.find(region: NAIROBI[:nearest], vscs_target: :production)
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(NAIROBI[:location])
      disable_stamp(stamp)

      assert_equal "WestEurope", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, client_ip: "1.2.3.4")
    end

    test "it finds the next best backup if both the primary and backup stamps are unavailable" do
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])

      stamp = Codespaces::VscsServiceStamp.find(region: BOSTON[:nearest], vscs_target: :production)
      # Grab its first backup so we can disable it both.
      backup = stamp.backup(user: @user)
      # Pretend all our regions are in the same geo.
      Codespaces::Locations::Region.any_instance.stubs(geo: stamp.geo)

      disable_stamp(stamp)
      disable_stamp(backup)

      assert_equal "WestUs3", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, client_ip: "1.2.3.4")
    end

    context "proxima", skip_enterprise: true do
      test "uses the proxima region when nearby" do
        GitHub.stubs(:codespaces_stamp_azure_geo).returns("apac")
        on_multi_tenant_enterprise(tenant: @business) do
          GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(NAIROBI[:location])

          assert_equal NAIROBI[:nearest], Codespaces::GetRegionForUser.call(user: @user, repository: @repo, client_ip: "1.2.3.4")
        end
      end
    end
  end

  context "with a requested_location" do
    test "raises if passed an invalid location" do
      assert_raises(Codespaces::Locations::Region::InvalidError) do
        Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_location: "FooBar")
      end
    end

    test "it works when provided a named geo directly" do
      # Boston, so UK South is closer than WestEurope
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])

      assert_equal "UkSouth", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_location: "EuropeWest")
    end

    test "it allows a named region to be provided but uses its geo" do
      # Boston, so UK South is closer than WestEurope
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])

      # We ignore the requested region and jump up to its geo instead.
      assert_equal "UkSouth", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_location: "WestEurope")
    end

    test "it uses the named region directly for codespaces_developers" do
      GitHub.flipper[:codespaces_developer].enable(@user)
      # Boston, so UK South is closer than WestEurope
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])

      # We use the requested region directly even though UkSouth is closer within the region's geo.
      assert_equal "WestEurope", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_location: "WestEurope")
    end
  end

  context "with prebuilds configured" do
    test "uses the closest region with prebuilds available" do
      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])
      Codespaces::Prebuilds.expects(:configured?).with(@repo).returns(true)
      stamp = Codespaces::VscsServiceStamp.find(region: BOSTON[:nearest], vscs_target: :production)
      stamp.stubs(prebuilds_available: false)

      assert_equal "EastUs2", Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
    end

    test "ignore prebuild availability if conflicting with network configuration", skip_enterprise: true do
      test_region = Codespaces::VscsServiceStamp.find(region: BOSTON[:nearest], vscs_target: :production).region.id

      user = create(:user)
      org = setup_vnet_injection_org(admin: user, regions: [test_region])
      repo = create(:private_repository, owner: org)

      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])
      Codespaces::Prebuilds.expects(:configured?).with(repo).returns(true)
      stamp = Codespaces::VscsServiceStamp.find(region: BOSTON[:nearest], vscs_target: :production)
      stamp.stubs(prebuilds_available: false)

      assert_equal test_region, Codespaces::GetRegionForUser.call(user:, repository: repo)
    end

    test "prefers prebuild availability if network config includes them", skip_enterprise: true do
      prebuild_available_region = RALEIGH[:nearest]
      prebuild_unavailable_region = BOSTON[:nearest]

      user = create(:user)
      org = setup_vnet_injection_org(admin: user, regions: [prebuild_available_region, prebuild_unavailable_region])
      repo = create(:private_repository, owner: org)

      GitHub.context.push(actor_ip: "1.2.3.4")
      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(BOSTON[:location])
      Codespaces::Prebuilds.expects(:configured?).with(repo).returns(true)
      stamp = Codespaces::VscsServiceStamp.find(region: prebuild_unavailable_region, vscs_target: :production)
      stamp.stubs(prebuilds_available: false)

      assert_equal prebuild_available_region, Codespaces::GetRegionForUser.call(user:, repository: repo)
    end
  end

  context "proxima", skip_enterprise: true do
    test "uses an appropriate region regardless of location" do
      GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

      on_multi_tenant_enterprise(tenant: @business) do
        assert_equal "WestEurope", Codespaces::GetRegionForUser.call(user: @user, repository: @repo)
      end
    end

    test "allows a geo to be specified as long as it contains at least one region allowed by proxima" do
      GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

      on_multi_tenant_enterprise(tenant: @business) do
        assert_equal "WestEurope", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_geo: "EuropeWest")
      end
    end

    test "raises if a specific region is requested but it is disallowed by proxima" do
      GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

      on_multi_tenant_enterprise(tenant: @business) do
        assert_raises(Codespaces::Locations::Region::InvalidError) do
          assert_equal "WestEurope", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_region: "EastUs")
        end
      end
    end

    test "raises if a specific geo is requested but it contains no regions allowed by proxima" do
      GitHub.stubs(:codespaces_stamp_azure_geo).returns("eu")

      on_multi_tenant_enterprise(tenant: @business) do
        assert_raises(Codespaces::Locations::Geo::InvalidError) do
          assert_equal "WestEurope", Codespaces::GetRegionForUser.call(user: @user, repository: @repo, requested_geo: "UsEast")
        end
      end
    end
  end

  context "with a network configuration", skip_enterprise: true do
    test "uses the region network configuration contains if only one" do
      test_region = "EastUs2"

      user = create(:user)
      org = setup_vnet_injection_org(admin: user, regions: [test_region])
      repo = create(:private_repository, owner: org)

      assert_equal(test_region, Codespaces::GetRegionForUser.call(user: user, repository: repo))
    end

    test "uses the requested region if the network configuration includes it" do
      test_region = "EastUs2"

      user = create(:user)
      org = setup_vnet_injection_org(admin: user, regions: [test_region, "WestUs3"])
      repo = create(:private_repository, owner: org)

      assert_equal("WestUs3", Codespaces::GetRegionForUser.call(user: user, repository: repo, requested_geo: "UsWest"))
    end
  end

  def enable_stamp(stamp)
    target_suffix = stamp.vscs_target == :production ? "" : "_#{stamp.vscs_target}"
    GitHub.flipper["codespaces_region_override_rejection_#{stamp.region.id.downcase}"].disable
    GitHub.flipper["codespaces_region_rejecting_creates_#{stamp.region.id.downcase}#{target_suffix}"].disable
    GitHub.flipper["codespaces_region_rejecting_resumes_#{stamp.region.id.downcase}#{target_suffix}"].disable
  end

  def disable_stamp(stamp)
    target_suffix = stamp.vscs_target == :production ? "" : "_#{stamp.vscs_target}"
    GitHub.flipper["codespaces_region_override_rejection_#{stamp.region.id.downcase}"].disable
    GitHub.flipper["codespaces_region_rejecting_creates_#{stamp.region.id.downcase}#{target_suffix}"].enable
  end
end
