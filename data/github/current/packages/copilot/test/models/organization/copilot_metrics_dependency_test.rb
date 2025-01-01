# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::CopilotMetricsDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @member = create(:user)
    @business = create(:business)
    @org = create(:organization, admin: @owner, business: @business)
  end

  setup do
    @org.add_member(@member, action: :write)
  end

  context "copilot_metrics_enabled?" do
    test "returns true when enabled for the org" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      enable_feature_flag(:copilot_metrics_onboarding_timeline_page, @org)

      assert @org.copilot_metrics_enabled?(@owner)
    end

    test "returns true when enabled for the org's business" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      enable_feature_flag(:copilot_metrics_onboarding_timeline_page, @org.business)

      assert @org.copilot_metrics_enabled?(@owner)
    end

    test "returns false when not a member of the org" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      other_user = create(:user)
      refute @org.copilot_metrics_enabled?(other_user)
    end

    test "returns false for non-admin members" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      refute @org.copilot_metrics_enabled?(@member)
    end

    test "returns false when logged out" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      refute @org.copilot_metrics_enabled?(nil)
    end

    test "returns false when org doesn't have copilot_for_business" do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(false)
      enable_feature_flag(:copilot_metrics_onboarding_timeline_page, @org)
      refute @org.copilot_metrics_enabled?(@owner)
    end

    test "returns true when admin has the FF enabled", skip_if_feature_disabled: :copilot_metrics_onboarding_timeline_page do
      Copilot::Organization.any_instance.stubs(:has_copilot_for_business?).returns(true)
      assert @org.copilot_metrics_enabled?(@owner)
    end
  end
end
