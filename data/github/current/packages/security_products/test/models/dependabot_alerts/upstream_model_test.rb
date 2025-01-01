# typed: true
# frozen_string_literal: true

require "test_helper"

class DependabotAlerts::UpstreamModelTest < GitHub::TestCase
  fixtures do
    @vulnerability = create(:vulnerability, severity: "high")
  end

  setup do
    ::SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:instrument_vulnerability_update_events?).returns(false)
  end

  context "vulnerability updates" do
    test "calls RefreshDependabotAlertsStateJob with changes arg if feature flag is enabled" do
      ::SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:instrument_vulnerability_update_events?).returns(true)
      vvr_list = @vulnerability.vulnerable_version_ranges

      assert_enqueued_with(job: RefreshDependabotAlertsStateJob, args: [vulnerable_version_range_id: vvr_list.first.id, changes: ["severity"]]) do
        @vulnerability.instrument_dependabot_alerts_upstream_change(event: :update, changes: ["severity"])
      end
    end

    test "calls RefreshDependabotAlertsStateJob without severity arg if feature flag is enabled if feature flag is disabled" do
      vvr_list = @vulnerability.vulnerable_version_ranges

      assert_enqueued_with(job: RefreshDependabotAlertsStateJob, args: [vulnerable_version_range_id: vvr_list.first.id]) do
        @vulnerability.instrument_dependabot_alerts_upstream_change(event: :update, changes: ["severity"])
      end
    end
  end
end
