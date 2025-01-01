# typed: true
# frozen_string_literal: true

require "json"
require "datadog_api_client"
require "report_axe_base"

class ReportAxeViolations < ReportAxeBase
  def submit_report!
    JSON.parse(File.read(@artifact_path)).each do |service, violation_data|
      violations = violation_data["violations"]

      # Get the current timestamp, but round down to nearest hour to avoid overlap with the next hour
      t = Time.now
      timestamp = (t - t.sec - ((t.min % 60) * 60)).to_i

      # loop through violations
      violations.each do |violation|
        # Submit route count with axe coverage
        @series[:axe_violations] << DatadogAPIClient::V1::Series.new({
          metric: "accessibility.axe_violations.count",
          points: [[timestamp, 1]],
          type: "gauge",
          tags: ["repo:github/github", "catalog_service:#{service}", "violation:#{violation["violation_id"]}", "impact:#{violation["impact"]}"]
        })
      end
    end

    submit_metrics!(@series[:axe_violations])
  end
end
