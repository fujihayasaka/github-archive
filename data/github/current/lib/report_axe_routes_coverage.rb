# typed: true
# frozen_string_literal: true

require "json"
require "datadog_api_client"
require "report_axe_base"

class ReportAxeRoutesCoverage < ReportAxeBase
  def submit_report!
    JSON.parse(File.read(@artifact_path)).each do |coverage_data|
      percentage = coverage_data["percentage"]
      with_coverage_count = coverage_data["routes_with_axe_coverage"].count
      without_coverage_count = coverage_data["routes_without_axe_coverage"].count
      service = coverage_data["service"]

      # Get the current timestamp, but round down to nearest hour to avoid overlap with the next hour
      t = Time.now
      timestamp = (t - t.sec - ((t.min % 60) * 60)).to_i

      # Submit route count with axe coverage
      @series[:routes_with_axe_coverage] << DatadogAPIClient::V1::Series.new({
        metric: "accessibility.axe_routes_with_coverage.count",
        points: [[timestamp, with_coverage_count]],
        type: "gauge",
        tags: ["repo:github/github", "catalog_service:#{service}"]
      })

      # Submit route count without axe coverage
      @series[:routes_without_axe_coverage] << DatadogAPIClient::V1::Series.new({
        metric: "accessibility.axe_routes_without_coverage.count",
        points: [[timestamp, without_coverage_count]],
        type: "gauge",
        tags: ["repo:github/github", "catalog_service:#{service}"]
      })
    end

    submit_metrics!(@series[:routes_with_axe_coverage] + @series[:routes_without_axe_coverage])
  end
end
