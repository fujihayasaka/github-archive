# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::ActionsMetricsDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @rando = create(:user)
    @business = create(:business, :metered_ghec)
    @org = create(:organization, admin: @owner, business: @business)
    @standalone_org = create(:organization, admin: @owner)
  end

  setup do
    enable_feature_flag(:actions_usage_metrics, @owner)
  end

  context "insights_enabled?" do
    test "returns true when org has enterprise plan", skip_enterprise: true, skip_with_all_emus: true do
      assert @org.insights_enabled?
    end

    test "returns false when org does not have enterprise plan and actions_usage_metrics disabled", skip_enterprise: true, skip_with_all_emus: true do
      disable_feature_flag(:actions_usage_metrics)
      refute @standalone_org.insights_enabled?
    end

    if GitHub.single_tenant_enterprise?
      test "does not display for single tenant enterprise" do
        refute @org.insights_enabled?
      end
    end

    if GitHub.multi_tenant_enterprise?
      test "can display for multi tenant enterprise" do
        assert @org.insights_enabled?
      end
    end
  end

  if !GitHub.single_tenant_enterprise?
    context "has_insights_content_available_for?" do
      test "returns true if has tab content" do
        assert @org.has_insights_content_available_for?(@owner)
      end

      test "returns false if insights has no content" do
        @org.stubs(:insights_enabled?).returns(true)
        @org.stubs(:dependency_insights_enabled_for?).returns(false)
        @org.stubs(:actions_usage_metrics_enabled?).returns(false)
        @org.stubs(:api_insights_enabled?).returns(false)
        refute @org.has_insights_content_available_for?(@owner)
      end

      test "return false if insights" do
        @org.stubs(:insights_enabled?).returns(false)
        refute @org.has_insights_content_available_for?(@owner)
      end

      test "returns true if not GHEC, but usage metrics is available" do
        @standalone_org.stubs(:not_ghes_and_biz_plus?).returns(false)
        @standalone_org.stubs(:business_plus?).returns(false)
        @standalone_org.stubs(:dependency_insights_enabled_for?).returns(false)
        @standalone_org.stubs(:api_insights_enabled?).returns(false)

        @standalone_org.stubs(:proxima_or_dotcom?).returns(true)
        @standalone_org.stubs(:actions_usage_metrics_enabled?).returns(true)

        assert @standalone_org.has_insights_content_available_for?(@owner)
      end
    end
  end
end
