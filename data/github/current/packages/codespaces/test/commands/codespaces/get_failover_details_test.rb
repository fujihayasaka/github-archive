# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/secrets_test_helpers"

class Codespaces::GetFailoverDetailsTest < GitHub::TestCase
  include DogstatsTestHelpers
  include SecretsTestHelper

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
  PHOENIX = {
    name: "Phoenix",
    location: { latitude: 33.4484, longitude: -112.0740 },
    nearest: "WestUs3",
  }

  fixtures do
    @user = create(:user)
  end

  test "there are no failover_details for resumes if flag is disabled" do
    requested_loc = NAIROBI
    backup_loc = BOSTON
    reject_feature_flag_name = "codespaces_region_rejecting_resumes_#{requested_loc[:nearest].downcase}"
    GitHub.flipper[reject_feature_flag_name.to_sym].disable

    assert_nil Codespaces::GetFailoverDetails.call(region: requested_loc[:nearest], user: @user, vscs_target: :production, is_copilot_workspace: false)
    assert_dogstats_increment(1, "codespaces.location_assignment", tags: ["location_reason:resume", "location:#{requested_loc[:nearest]}"])
  end

  test "backup region is designated for resumes if flag is enabled with a single in-geo option" do
    requested_loc = BOSTON
    GitHub.flipper["codespaces_region_rejecting_resumes_eastus".to_sym].enable
    GitHub.flipper["codespaces_region_rejecting_resumes_eastus2".to_sym].disable

    expected = { failoverEnabled: true, failoverRegion: "EastUs2" }

    assert_equal expected, Codespaces::GetFailoverDetails.call(region: requested_loc[:nearest], user: @user, vscs_target: :production, is_copilot_workspace: false)
    assert_dogstats_increment(1, "codespaces.location_assignment_rejected", tags: ["location_reason:resume", "location:#{requested_loc[:nearest]}"])
    assert_dogstats_increment(1, "codespaces.location_assignment", tags: ["location_reason:resume", "location:#{requested_loc[:nearest]}"])
    assert_dogstats_increment(1, "codespaces.location_assignment_reassigned", tags: ["location_reason:resume", "location:EastUs2"])
  end

  test "backup region is closest to user for resumes if flag is enabled with multiple in-geo options" do
    requested_loc = BOSTON
    GitHub.context.push(actor_ip: "1.2.3.4")
    GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(requested_loc[:location])
    GitHub.flipper["codespaces_region_rejecting_resumes_eastus".to_sym].enable
    GitHub.flipper["codespaces_region_rejecting_resumes_eastus2".to_sym].disable

    expected = { failoverEnabled: true, failoverRegion: "EastUs2" }

    stamp = Codespaces::VscsServiceStamp.find(region: requested_loc[:nearest], vscs_target: :production)
    stamp.stubs(:available_backups).returns(Codespaces::VscsServiceStamp.where(vscs_target: :production).without(stamp))

    assert_equal expected, Codespaces::GetFailoverDetails.call(region: requested_loc[:nearest], user: @user, vscs_target: :production, is_copilot_workspace: false)
  end

  test "backup region works if IP geolocation fails for resumes if flag is enabled with multiple in-geo options" do
    requested_loc = BOSTON
    GitHub.flipper["codespaces_region_rejecting_resumes_eastus".to_sym].enable
    GitHub.flipper["codespaces_region_rejecting_resumes_eastus2".to_sym].disable

    expected = { failoverEnabled: true, failoverRegion: "EastUs2" }

    Codespaces::Locations::RegionLocator.any_instance.stubs(:from_ip_location_lookup).returns(nil)
    stamp = Codespaces::VscsServiceStamp.find(region: requested_loc[:nearest], vscs_target: :production)
    stamp.stubs(:available_backups).returns(Codespaces::VscsServiceStamp.where(vscs_target: :production).without(stamp))

    assert_equal expected, Codespaces::GetFailoverDetails.call(region: requested_loc[:nearest], user: @user, vscs_target: :production, is_copilot_workspace: false)
  end

  test "failover_details are returned if multiple regions are failed over with multiple in-geo options" do
    stamps = [
      Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production),
      Codespaces::VscsServiceStamp.find(region: "EastUs2", vscs_target: :production),
      Codespaces::VscsServiceStamp.find(region: "WestUs2", vscs_target: :production),
      Codespaces::VscsServiceStamp.find(region: "WestUs3", vscs_target: :production),
    ]

    GitHub.context.push(actor_ip: "1.2.3.4")
    GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(PHOENIX[:location])

    eastus = Codespaces::VscsServiceStamp.find(region: "EastUs", vscs_target: :production)
    westus3 = Codespaces::VscsServiceStamp.find(region: "WestUs3", vscs_target: :production)
    GitHub.flipper["codespaces_region_rejecting_resumes_eastus".to_sym].enable
    GitHub.flipper["codespaces_region_rejecting_resumes_westus3".to_sym].enable
    # Skip the FF stuff in favor of explicitly returning all "available" stamps to pretend we have a N>2 region geo.
    eastus.stubs(:available_backups).returns(Codespaces::VscsServiceStamp.where(vscs_target: :production).without(eastus, westus3))

    expected = { failoverEnabled: true, failoverRegion: "WestUs2" }

    assert_equal expected, Codespaces::GetFailoverDetails.call(region: "EastUs", user: @user, vscs_target: :production, is_copilot_workspace: false)
  end
end
