# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Metrics::UsageMetricsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @org = create(:copilot_for_business_enabled_organization)
    @business = @org.business
  end

  setup do
    disable_feature_flag(:copilot_chat_metrics, @org)
    disable_feature_flag(:copilot_chat_metrics, @business)
  end

  context "initialize" do
    test "it handles an organization" do
      organization = create(:organization)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(organization: organization)
      assert_equal :organization, usage_metrics.instance_variable_get(:@entity_type)
    end

    test "it handles a business" do
      business = create(:business)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(business: business)
      assert_equal :business, usage_metrics.instance_variable_get(:@entity_type)
    end

    test "it handles a team" do
      team = create(:team)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(team: team)
      assert_equal :team, usage_metrics.instance_variable_get(:@entity_type)
    end

    test "it handles an EnterpriseTeam" do
      enterprise_team = create(:enterprise_team)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(enterprise_team: enterprise_team)
      assert_equal :enterprise_team, usage_metrics.instance_variable_get(:@entity_type)
    end
  end unless TestEnv.enterprise?

  context "include_chat_metrics?" do
    test "it returns true if the organization has the feature enabled" do
      organization = create(:organization)
      enable_feature_flag(:copilot_chat_metrics, organization)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(organization: organization)

      assert usage_metrics.send(:include_chat_metrics?)
    end

    test "it returns true if the organization's business has the feature enabled" do
      business = create(:business)
      create(:organization, business: business)
      enable_feature_flag(:copilot_chat_metrics, business)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(business: business)

      assert usage_metrics.send(:include_chat_metrics?)
    end

    test "it returns false if the organization does not have the feature enabled" do
      organization = create(:organization)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(organization: organization)

      refute usage_metrics.send(:include_chat_metrics?)
    end

    test "it returns false if the organization's business does not have the feature enabled" do
      business = create(:business)
      create(:organization, business: business)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(business: business)

      refute usage_metrics.send(:include_chat_metrics?)
    end

    test "it returns true if the enterprise team's business has the feature enabled" do
      enterprise_team = create(:enterprise_team)
      enable_feature_flag(:copilot_chat_metrics, enterprise_team.business)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(enterprise_team: enterprise_team)

      assert usage_metrics.send(:include_chat_metrics?)
    end

    test "it returns false if the enterprise team's business does not have the feature enabled" do
      enterprise_team = create(:enterprise_team)
      disable_feature_flag(:copilot_chat_metrics, enterprise_team.business)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(enterprise_team: enterprise_team)

      refute usage_metrics.send(:include_chat_metrics?)
    end

    test "it returns true if the team's organization has the feature enabled" do
      organization = create(:organization)
      enable_feature_flag(:copilot_chat_metrics, organization)
      team = create(:team, organization: organization)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(team: team)

      assert usage_metrics.send(:include_chat_metrics?)
    end

    test "it returns true if the team's organization's business has the feature enabled" do
      business = create(:business)
      organization = create(:organization, business: business)
      enable_feature_flag(:copilot_chat_metrics, business)
      team = create(:team, organization: organization)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(team: team)

      assert usage_metrics.send(:include_chat_metrics?)
    end

    test "it returns false if the team's organization does not have the feature enabled" do
      organization = create(:organization)
      team = create(:team, organization: organization)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(team: team)

      refute usage_metrics.send(:include_chat_metrics?)
    end

    test "it returns false if the team's organization's business does not have the feature enabled" do
      business = create(:business)
      organization = create(:organization, business: business)
      team = create(:team, organization: organization)
      usage_metrics = Copilot::Metrics::UsageMetrics.new(team: team)

      refute usage_metrics.send(:include_chat_metrics?)
    end
  end unless TestEnv.enterprise?
end
