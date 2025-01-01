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

      # Map of total number of violating nodes observed for a given set of tags.
      total_node_count_map = {}
      violations.each do |violation|
        violation_id = violation["violation_id"]
        controller = violation["controller"]
        action = violation["action"]
        impact = violation["impact"]
        # Report number of violation seen.
        @series[:axe_violations] << DatadogAPIClient::V1::Series.new({
          metric: "accessibility.axe_violations.count",
          points: [[timestamp, 1]],
          type: "gauge",
          tags: ["repo:github/github", "catalog_service:#{service}", "violation:#{violation_id}", "controller:#{controller}", "action:#{action}", "impact:#{impact}"]
        })

        # With `gauge`, Datadog only reports the last reported value for a given set of tags.
        # If a set of tags appears multiple times, we want to sum the nodes.
        # Let's calculate the total nodes so it's ready to submit to Datadog.
        identifier = "#{service},#{violation_id},#{controller},#{action},#{impact}"
        if total_node_count_map[identifier]
          total_node_count_map[identifier][:node_count] += violation["node_count"]
        else
          total_node_count_map[identifier] = {
            service: service,
            violation_id: violation_id,
            node_count: violation["node_count"],
            controller: controller,
            action: action,
            impact: impact
          }
        end
      end

      # Report total number of violating nodes seen.
      total_node_count_map.each do |_, data|
        @series[:axe_violating_nodes] << DatadogAPIClient::V1::Series.new({
          metric: "accessibility.axe_violating_nodes.count",
          points: [[timestamp, data[:node_count]]],
          type: "gauge",
          tags: ["repo:github/github", "catalog_service:#{data[:service]}", "violation:#{data[:violation_id]}", "controller:#{data[:controller]}", "action:#{data[:action]}", "impact:#{data[:impact]}"]
        })
      end
    end

    submit_metrics!(@series[:axe_violations])
    submit_metrics!(@series[:axe_violating_nodes])
  end
end
