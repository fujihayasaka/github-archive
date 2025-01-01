# typed: true
# frozen_string_literal: true

require "test_helper"

class DependabotAlerts::UpstreamModelTest < GitHub::TestCase
  fixtures do
    @vulnerability = create(:vulnerability, severity: "high")
  end

  context "vulnerability updates" do
    test "calls RefreshDependabotAlertsStateJob with changes arg" do
      vvr_list = @vulnerability.vulnerable_version_ranges

      assert_enqueued_with(job: RefreshDependabotAlertsStateJob, args: [vulnerable_version_range_id: vvr_list.first.id, changes: ["severity"]]) do
        @vulnerability.instrument_dependabot_alerts_upstream_change(event: :update, changes: ["severity"])
      end
    end
  end
end
