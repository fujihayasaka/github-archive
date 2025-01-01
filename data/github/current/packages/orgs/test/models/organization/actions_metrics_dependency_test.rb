# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::ActionsMetricsDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @rando = create(:user)
    @business = create(:business, :metered_ghec)
    @org = create(:organization, admin: @owner, business: @business)
    @standalone_org = create(:organization)
  end

  setup do
    GitHub.flipper[:api_insights].enable(@owner)
    GitHub.flipper[:actions_usage_metrics].enable(@owner)
  end

  context "insights_enabled?" do
    test "returns true when org has enterprise plan", skip_enterprise: true, skip_with_all_emus: true do
      assert @org.insights_enabled?
    end

    test "returns false when org does not have enterprise plan", skip_enterprise: true, skip_with_all_emus: true do
      refute @standalone_org.insights_enabled?
    end

    if GitHub.single_tenant_enterprise?
      test "does not display for single tenant enterprise" do
        refute @org.insights_enabled?
      end
    end

    if GitHub.multi_tenant_enterprise?
      test "does not display for multi tenant enterprise" do
        refute @org.insights_enabled?
      end
    end
  end

  context "has_insights_content_available_for?" do
    test "returns true if has tab content", skip_enterprise: true, skip_with_all_emus: true do
      assert @org.has_insights_content_available_for?(@owner)
    end

    test "returns false if insights has no content", skip_enterprise: true, skip_with_all_emus: true do
      @org.stubs(:dependency_insights_enabled_for?).returns(false)
      @org.stubs(:actions_usage_metrics_enabled?).returns(false)
      @org.stubs(:api_insights_enabled?).returns(false)
      refute @org.has_insights_content_available_for?(@owner)
    end

    test "return false if insights is not enabled", skip_enterprise: true, skip_with_all_emus: true do
      refute @standalone_org.has_insights_content_available_for?(@owner)
    end
  end
end
