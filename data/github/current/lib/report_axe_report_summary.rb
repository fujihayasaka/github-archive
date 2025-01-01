# typed: true
# frozen_string_literal: true

require "json"
require "datadog_api_client"
require "report_axe_base"

class ReportAxeReportSummary < ReportAxeBase

  # Report total number of Axe scans that take place in our builds, along with route and service info.
  def submit_report!
    # Get the current timestamp, but round down to nearest hour to avoid overlap with the next hour
    t = Time.now
    timestamp = (t - t.sec - ((t.min % 60) * 60)).to_i

    map = track_axe_report_status_for_each_route(@artifact_path)

    map.values.each do |obj|
      service = obj[:service]
      controller = obj[:controller]
      action = obj[:action]

      # Report number of passing scans for a given route
      passing_scan_count = obj[:passing_scan_count]
      if passing_scan_count > 0
        @series[:axe_scan_report] << DatadogAPIClient::V1::Series.new({
          metric: "accessibility.axe_report_summary.count",
          points: [[timestamp, passing_scan_count]],
          type: "gauge",
          tags: [
            "repo:github/github",
            "catalog_service:#{obj[:service]}",
            "controller:#{obj[:controller]}",
            "action:#{obj[:action]}",
            "passing_axe_scan:true"
          ]
        })
      end

      failing_scan_count = obj[:failing_scan_count]
      # Report number of failing scans for a given route
      if failing_scan_count > 0
        @series[:axe_scan_report] << DatadogAPIClient::V1::Series.new({
          metric: "accessibility.axe_report_summary.count",
          points: [[timestamp, failing_scan_count]],
          type: "gauge",
          tags: [
            "repo:github/github",
            "catalog_service:#{obj[:service]}",
            "controller:#{obj[:controller]}",
            "action:#{obj[:action]}",
            "passing_axe_scan:false"
          ] })
      end
    end

    submit_metrics!(@series[:axe_scan_report])
  end

  private

  # We track the number of passing scans and failing scans per unique route scanned.
  # We use the service,controller,action to identify a unique route.
  def track_axe_report_status_for_each_route(artifact_path)
    map = {}
    File.readlines(artifact_path).each do |line|
      line_to_json = JSON.parse(line)
      service = line_to_json["service"]
      controller = line_to_json["controller"]
      action = line_to_json["action"]
      passing_axe_scan = line_to_json["passingScan"]

      # The same route may be Axe scanned multiple times.
      # We'll measure the number of passing scan and failing scans that take place at the service/controller/action level.
      key = "service:#{service},controller:#{controller},action:#{action}"
      if map.key?(key)
        existing_value = map[key]
        passing_axe_scan == true ? existing_value[:passing_scan_count] += 1 : existing_value[:failing_scan_count] += 1
        map[key] = existing_value
      else
        map[key] = {
          service: service,
          controller: controller,
          action: action,
          passing_scan_count: passing_axe_scan == true ? 1 : 0,
          failing_scan_count: passing_axe_scan != true ? 1 : 0
        }
      end
    end
    map
  end
end
