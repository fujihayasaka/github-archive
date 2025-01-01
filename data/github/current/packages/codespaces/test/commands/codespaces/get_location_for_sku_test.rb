# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::GetLocationForSkuTest < GitHub::TestCase
  fixtures do
    GitHub.flipper[:codespaces_linux_premium_gpu].enable
    @user = create(:user)
  end

  test "returns the requested location if not using a GPU sku" do
    location = Codespaces::GetLocationForSKU.call(
      location: "UkSouth",
      sku_name: "standardLinux",
      vscs_target: Codespaces::Vscs.default_target,
      user: @user
    )
    assert_equal "UkSouth", location
  end

  test "returns the requested location if the location supports GPU skus" do
    location = Codespaces::GetLocationForSKU.call(
      location: "EastUs",
      sku_name: "premiumLinuxGPU",
      vscs_target: Codespaces::Vscs.default_target,
      user: @user
    )
    assert_equal "EastUs", location
  end

  test "finds a suitable fallback location when the requested location does not support GPU skus" do
    location = Codespaces::GetLocationForSKU.call(
      location: "UkSouth",
      sku_name: "premiumLinuxGPU",
      vscs_target: Codespaces::Vscs.default_target,
      user: @user
    )
    assert_equal "WestEurope", location
  end

  test "uses a GPU-enabled backup location if the primary sku fallback location is unavailable" do
    # This requires a chain of backups like INC->ASSE->AUE but we're not set up like that currently.
    skip "We're currently not configured in a way that this can happen"
    GitHub.flipper[:codespaces_region_rejecting_creates_southeastasia].enable
    GitHub.flipper[:codespaces_region_override_rejection_southeastasia].disable
    location = Codespaces::GetLocationForSKU.call(
      location: "CentralIndia",
      sku_name: "premiumLinuxGPU",
      vscs_target: Codespaces::Vscs.default_target,
      user: @user
    )
    assert_equal "AustraliaEast", location
  end

  test "raises if the sku fallback location is unavaialble and its backup location does not support GPU skus" do
    GitHub.flipper[:codespaces_region_rejecting_creates_westeurope].enable
    GitHub.flipper[:codespaces_region_override_rejection_westeurope].disable
    assert_raises Codespaces::Locations::Region::UnavailableError do
      Codespaces::GetLocationForSKU.call(
        location: "UkSouth",
        sku_name: "premiumLinuxGPU",
        vscs_target: Codespaces::Vscs.default_target,
        user: @user
      )
    end
  end

  test "raises if both the sku fallback location and its backup are unavailable" do
    GitHub.flipper[:codespaces_region_rejecting_creates_southeastasia].enable
    GitHub.flipper[:codespaces_region_override_rejection_southeastasia].disable
    GitHub.flipper[:codespaces_region_rejecting_creates_australiaeast].enable
    GitHub.flipper[:codespaces_region_override_rejection_australiaeast].disable
    assert_raises Codespaces::Locations::Region::UnavailableError do
      Codespaces::GetLocationForSKU.call(
        location: "CentralIndia",
        sku_name: "premiumLinuxGPU",
        vscs_target: Codespaces::Vscs.default_target,
        user: @user
      )
    end
  end
end
