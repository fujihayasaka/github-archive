# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesVscsServiceStampAvailabilityTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    @stamp = Codespaces::VscsServiceStamp.find(region: "WestUs2", vscs_target: :production)
    @availability = Codespaces::VscsServiceStampAvailability.new(@stamp)
    disable_feature_flag("codespaces_region_override_rejection_#{@stamp.region.id.downcase}")
    disable_feature_flag("codespaces_region_rejecting_creates_#{@stamp.region.id.downcase}")
    disable_feature_flag("codespaces_region_rejecting_resumes_#{@stamp.region.id.downcase}")
  end

  context "available_to?" do
    test "allows GA stamps for normal users" do
      @stamp.stubs(:ga?).returns(true)
      assert @availability.available_to?(user: @user)
    end

    test "prevents normal users from using non-GA stamps" do
      @stamp.stubs(:ga?).returns(false)
      disable_feature_flag(:codespaces_developer, @user)
      refute @availability.available_to?(user: @user)
    end

    test "allows non-GA stamps for codespaces developers" do
      @stamp.stubs(:ga?).returns(false)
      enable_feature_flag(:codespaces_developer, @user)
      assert @availability.available_to?(user: @user)
    end
  end

  context "available_for_creates?" do
    test "respects availability" do
      @stamp.stubs(:ga?).returns(false)
      refute @availability.available_for_creates?(user: @user)
    end

    test "respects the create failover FF" do
      enable_feature_flag("codespaces_region_rejecting_creates_#{@stamp.region.id.downcase}", @user)
      refute @availability.available_for_creates?(user: @user)
    end

    test "but allows it to be overridden" do
      enable_feature_flag("codespaces_region_rejecting_creates_#{@stamp.region.id.downcase}", @user)
      enable_feature_flag("codespaces_region_override_rejection_#{@stamp.region.id.downcase}", @user)
      assert @availability.available_for_creates?(user: @user)
    end
  end

  context "available_for_resumes?" do
    test "respects availability" do
      @stamp.stubs(:ga?).returns(false)
      refute @availability.available_for_resumes?(user: @user)
    end

    test "respects the resume failover FF" do
      enable_feature_flag("codespaces_region_rejecting_resumes_#{@stamp.region.id.downcase}", @user)
      refute @availability.available_for_resumes?(user: @user)
    end
  end

  context "available?" do
    test "respects availability" do
      @stamp.stubs(:ga?).returns(false)
      refute @availability.available?(user: @user)
    end

    test "respects the create failover FF" do
      enable_feature_flag("codespaces_region_rejecting_creates_#{@stamp.region.id.downcase}", @user)
      refute @availability.available?(user: @user)
    end

    test "respects the resume failover FF" do
      enable_feature_flag("codespaces_region_rejecting_resumes_#{@stamp.region.id.downcase}", @user)
      refute @availability.available?(user: @user)
    end
  end
end
