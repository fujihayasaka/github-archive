# typed: true
# frozen_string_literal: true

require "test_helper"

class Business::ActionsMetricsDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @rando = create(:user)
    @business = create :business, owners: [@owner]
    @org = create(:organization, admin: @owner, business: @business)
    @org.add_member(@rando)
  end

  setup do
    enable_feature_flag(:actions_usage_metrics, @owner)
    enable_feature_flag(:actions_usage_metrics_enterprise, @owner)
  end

  context "insights_enabled?" do
    if GitHub.single_tenant_enterprise?
      test "does not display for single tenant enterprise" do
        refute @business.insights_enabled?(@owner)
      end
    end

    if GitHub.multi_tenant_enterprise?
      test "can display for multi tenant enterprise" do
        assert @business.insights_enabled?(@owner)
      end
    end
  end

  if !GitHub.single_tenant_enterprise?
    context "actions_usage_metrics_enabled?" do
      test "disabled without enterprise" do
        disable_feature_flag(:actions_usage_metrics_enterprise, @owner)
        refute @business.actions_usage_metrics_enabled?(@owner)
      end

      test "returns false for non-owner" do
        refute @org.actions_usage_metrics_enabled?(@rando)
      end

      test "return true for owner" do
        assert @org.actions_usage_metrics_enabled?(@owner)
      end
    end
  end
end
