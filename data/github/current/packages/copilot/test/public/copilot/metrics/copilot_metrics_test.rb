# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/copilot_usage_metrics_test_helper"

class Copilot::Metrics::CopilotMetricsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include CopilotUsageMetricsTestHelper

  fixtures do
    @org = create(:copilot_for_business_enabled_organization)
    @business = @org.business
    @team = create(:team, organization: @org)
    @basic_enterprise = create(:business, :default_managed, seats_plan_type: :basic)
    @enterprise_team = create(:enterprise_team, business: @basic_enterprise)

    # creates metrics for the prior 6 days for each entity
    create_v2_usage_metrics(org: @org)
    create_v2_usage_metrics(team: @team)
    create_v2_usage_metrics(enterprise_team: @enterprise_team)
    create_v2_usage_metrics(business: @business)
  end

  setup do
    @org_copilot_metrics = Copilot::Metrics::CopilotMetrics.new(organization: @org)
    @business_copilot_metrics = Copilot::Metrics::CopilotMetrics.new(business: @business)
    @team_copilot_metrics = Copilot::Metrics::CopilotMetrics.new(team: @team)
    @enterprise_team_copilot_metrics = Copilot::Metrics::CopilotMetrics.new(enterprise_team: @enterprise_team)
  end

  context "initialize" do
    test "it handles an organization" do
      assert_equal :organization, @org_copilot_metrics.instance_variable_get(:@entity_type)
    end

    test "it handles a business" do
      assert_equal :business, @business_copilot_metrics.instance_variable_get(:@entity_type)
    end

    test "it handles a team" do
      assert_equal :team, @team_copilot_metrics.instance_variable_get(:@entity_type)
    end

    test "it handles an EnterpriseTeam" do
      assert_equal :enterprise_team, @enterprise_team_copilot_metrics.instance_variable_get(:@entity_type)
    end
  end unless TestEnv.enterprise?

  context "all_metrics" do
    test "it returns all metrics for an organization" do
      assert_equal 6, @org_copilot_metrics.send(:all_metrics).count
    end

    test "it returns all metrics for a business" do
      assert_equal 6, @business_copilot_metrics.send(:all_metrics).count
    end

    test "it returns all metrics for a team" do
      assert_equal 6, @team_copilot_metrics.send(:all_metrics).count
    end

    test "it returns all metrics for an EnterpriseTeam" do
      assert_equal 6, @enterprise_team_copilot_metrics.send(:all_metrics).count
    end
  end unless TestEnv.enterprise?

  context "metrics_between_dates" do
    test "it returns metrics between two dates for an organization" do
      assert_equal 3, @org_copilot_metrics.send(:metrics_between_dates, 3.days.ago.to_date, 1.day.ago.to_date).count
    end

    test "it returns metrics between two dates for a business" do
      assert_equal 3, @business_copilot_metrics.send(:metrics_between_dates, 3.days.ago.to_date, 1.day.ago.to_date).count
    end

    test "it returns metrics between two dates for a team" do
      assert_equal 3, @team_copilot_metrics.send(:metrics_between_dates, 3.days.ago.to_date, 1.day.ago.to_date).count
    end

    test "it returns metrics between two dates for an EnterpriseTeam" do
      assert_equal 3, @enterprise_team_copilot_metrics.send(:metrics_between_dates, 3.days.ago.to_date, 1.day.ago.to_date).count
    end
  end unless TestEnv.enterprise?

  context "payload" do
    test "it returns a payload for an organization" do
      assert_equal 6, @org_copilot_metrics.payload.length
    end

    test "it returns a payload for a business" do
      assert_equal 6, @business_copilot_metrics.payload.length
    end

    test "it returns a payload for a team" do
      assert_equal 6, @team_copilot_metrics.payload.length
    end

    test "it returns a payload for an EnterpriseTeam" do
      assert_equal 6, @enterprise_team_copilot_metrics.payload.length
    end
  end unless TestEnv.enterprise?
end
